-- Non-dbt Snowflake objects that the telco project depends on.
-- Purpose: discovery / translation test corpus.

use role ACCOUNTADMIN;

create warehouse if not exists TRANSFORM_WH with warehouse_size = 'MEDIUM' auto_suspend = 60 auto_resume = true;
create resource monitor if not exists TELCO_RM with credit_quota = 500 triggers on 90 percent do suspend;
create database if not exists TELCO_PROD;
create schema if not exists TELCO_PROD.RAW;
create schema if not exists TELCO_PROD.AUDIT;

-- tags and policies
create tag if not exists TELCO_PROD.RAW.pii_level allowed_values 'none', 'low', 'high';

create masking policy if not exists TELCO_PROD.RAW.mask_email as (val string) returns string ->
    case when is_role_in_session('PII_READER') then val else '***MASKED***' end;

create row access policy if not exists TELCO_PROD.RAW.rap_region as (state string) returns boolean ->
    is_role_in_session('ADMIN') or exists (
        select 1 from TELCO_PROD.AUDIT.region_entitlement e
        where e.role_name = current_role() and e.state = state);

-- raw tables
create or replace table TELCO_PROD.RAW.CDR (
    cdr_id varchar, msisdn varchar, called_number varchar, call_type varchar,
    start_ts_raw varchar, duration_sec number(10,0), bytes_used number(18,0),
    cell_id varchar, roaming_flag varchar, raw_payload variant,
    loaded_at timestamp_ntz default current_timestamp()
) cluster by (to_date(loaded_at), msisdn) data_retention_time_in_days = 7;

create or replace table TELCO_PROD.RAW.SUBSCRIBERS (
    subscriber_id number autoincrement, msisdn varchar, full_name varchar,
    email varchar with masking policy TELCO_PROD.RAW.mask_email,
    dob date, activation_date date, status varchar, plan_id number,
    address variant, updated_at timestamp_ntz
);
create or replace table TELCO_PROD.RAW.PLANS (
    plan_id number, plan_name varchar, monthly_fee_cents number, data_gb number(8,2),
    voice_min number, sms_count number, valid_from date, valid_to date
);
create or replace table TELCO_PROD.RAW.INVOICES (
    invoice_id varchar, subscriber_id number, period_start date, period_end date,
    amount_cents number, tax_cents number, status varchar, lines variant, updated_at timestamp_ntz
);
create or replace table TELCO_PROD.RAW.PAYMENTS (
    payment_id varchar, invoice_id varchar, paid_at timestamp_ntz, amount_cents number, method varchar
);
create or replace table TELCO_PROD.RAW.NETWORK_EVENTS (
    event_id varchar, cell_id varchar, event_ts timestamp_ntz, event_json variant
);
create or replace table TELCO_PROD.RAW.TICKETS (
    ticket_id varchar, subscriber_id number, opened_at timestamp_ntz, closed_at timestamp_ntz, category varchar
);

alter table TELCO_PROD.RAW.SUBSCRIBERS modify column email set tag TELCO_PROD.RAW.pii_level = 'high';
alter table TELCO_PROD.RAW.SUBSCRIBERS add row access policy TELCO_PROD.RAW.rap_region on (msisdn);

-- stage, file format, pipe
create or replace file format TELCO_PROD.RAW.ff_json type = json strip_outer_array = true;
create or replace stage TELCO_PROD.RAW.stg_cdr url = 's3://telco-landing/cdr/'
    storage_integration = S3_INT file_format = TELCO_PROD.RAW.ff_json;

create or replace pipe TELCO_PROD.RAW.pipe_cdr auto_ingest = true as
    copy into TELCO_PROD.RAW.CDR (cdr_id, msisdn, called_number, call_type, start_ts_raw,
                                   duration_sec, bytes_used, cell_id, roaming_flag, raw_payload)
    from (select $1:id, $1:msisdn, $1:called, $1:type, $1:start, $1:dur, $1:bytes,
                 $1:cell, $1:roaming, $1 from @TELCO_PROD.RAW.stg_cdr);

-- external table over Parquet
create or replace external table TELCO_PROD.RAW.EXT_TOWER_LOG (
    cell_id varchar as (value:cell_id::varchar),
    reading float as (value:reading::float)
) location = @TELCO_PROD.RAW.stg_cdr/tower/ file_format = (type = parquet) auto_refresh = true;

-- streams and tasks (CDC)
create or replace stream TELCO_PROD.RAW.strm_cdr on table TELCO_PROD.RAW.CDR append_only = true;
create or replace stream TELCO_PROD.RAW.strm_subscribers on table TELCO_PROD.RAW.SUBSCRIBERS;

create or replace table TELCO_PROD.AUDIT.dbt_run_log (
    invocation_id varchar, node_id varchar, status varchar, exec_seconds float, logged_at timestamp_ntz
);

create or replace task TELCO_PROD.RAW.task_load_cdr_hourly
    warehouse = TRANSFORM_WH schedule = 'USING CRON 0 * * * * Asia/Kolkata'
    when system$stream_has_data('TELCO_PROD.RAW.strm_cdr')
as
    insert into TELCO_PROD.AUDIT.cdr_hourly_counts
    select date_trunc('hour', loaded_at), count(*) from TELCO_PROD.RAW.strm_cdr group by 1;

create or replace task TELCO_PROD.RAW.task_refresh_marts
    warehouse = TRANSFORM_WH after TELCO_PROD.RAW.task_load_cdr_hourly
as
    execute dbt project TELCO_PROD.ANALYTICS.telco_project args = 'build --select tag:marts';

alter task TELCO_PROD.RAW.task_refresh_marts resume;
alter task TELCO_PROD.RAW.task_load_cdr_hourly resume;

-- UDFs and procedures
create or replace function TELCO_PROD.RAW.normalize_msisdn(m varchar)
returns varchar language sql as
$$ regexp_replace(m, '[^0-9+]', '') $$;

create or replace function TELCO_PROD.RAW.bytes_to_gb_js(b float)
returns float language javascript as
$$ return B / 1073741824; $$;

create or replace function TELCO_PROD.RAW.risk_bucket(score float)
returns varchar language python runtime_version = '3.10' handler = 'f' as
$$
def f(score):
    return 'HIGH' if score > 0.7 else 'MEDIUM' if score > 0.4 else 'LOW'
$$;

create or replace procedure TELCO_PROD.RAW.sp_archive_cdr(days number)
returns varchar language sql as
$$
begin
    delete from TELCO_PROD.RAW.CDR where loaded_at < dateadd(day, -:days, current_timestamp());
    return 'ok';
end;
$$;

-- materialized view (Snowflake-only)
create or replace materialized view TELCO_PROD.RAW.mv_cdr_daily as
    select start_ts_raw::date d, call_type, count(*) c from TELCO_PROD.RAW.CDR group by 1, 2;

-- data share and grants
create or replace share TELCO_SHARE;
grant usage on database TELCO_PROD to share TELCO_SHARE;
grant select on all tables in schema TELCO_PROD.MARTS to role ANALYST_ROLE;
grant select on future tables in schema TELCO_PROD.MARTS to role ANALYST_ROLE;
