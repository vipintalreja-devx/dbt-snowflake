-- Non-dbt BigQuery objects the translated project depends on.
-- Replace `my-project` and region as needed.

-- Datasets (Snowflake: database + schema). 7 days time travel = max_time_travel_hours 168.
create schema if not exists `my-project.raw`   options (location = 'asia-south1', max_time_travel_hours = 168);
create schema if not exists `my-project.audit` options (location = 'asia-south1');

-- Warehouse / resource monitor -> none.
--   Compute: on-demand (pay per byte) or Editions with reservations + autoscaling.
--   Credit cap: project custom quota ("query usage per day") + billing budget alerts.
--   Per-query cap: maximum_bytes_billed in profiles.yml.

-- Tags / masking policy -> policy tags + data policies (created in Data Catalog taxonomy via console or API).
--   Attach policy tag "pii_high" to raw.subscribers.email, then a masking rule (SHA256 / nullify) per role.

-- Raw tables
create or replace table `my-project.raw.cdr` (
    cdr_id string, msisdn string, called_number string, call_type string,
    start_ts_raw string, duration_sec int64, bytes_used int64,
    cell_id string, roaming_flag string, raw_payload json,
    loaded_at datetime default current_datetime()
)
partition by date(loaded_at)
cluster by msisdn;

create or replace table `my-project.raw.subscribers` (
    subscriber_id int64, msisdn string, full_name string, email string,
    dob date, activation_date date, status string, plan_id int64,
    address json, updated_at datetime
);
create or replace table `my-project.raw.plans` (
    plan_id int64, plan_name string, monthly_fee_cents int64, data_gb numeric,
    voice_min int64, sms_count int64, valid_from date, valid_to date
);
create or replace table `my-project.raw.invoices` (
    invoice_id string, subscriber_id int64, period_start date, period_end date,
    amount_cents int64, tax_cents int64, status string, lines json, updated_at datetime
);
create or replace table `my-project.raw.payments` (
    payment_id string, invoice_id string, paid_at datetime, amount_cents int64, method string
);
create or replace table `my-project.raw.network_events` (
    event_id string, cell_id string, event_ts datetime, event_json json
);
create or replace table `my-project.raw.tickets` (
    ticket_id string, subscriber_id int64, opened_at datetime, closed_at datetime, category string
);

-- Row access policy (Snowflake row access policy)
create or replace row access policy rap_region
on `my-project.raw.subscribers`
grant to ('group:admin@example.com', 'group:north-analysts@example.com')
filter using (true);   -- replace with per-group predicate, e.g. json_value(address, '$.state') = 'Delhi'

-- Stage + pipe -> GCS bucket + load job. Batch load example:
load data into `my-project.raw.cdr` (cdr_id string, msisdn string, called_number string, call_type string,
    start_ts_raw string, duration_sec int64, bytes_used int64, cell_id string, roaming_flag string, raw_payload json)
from files (format = 'JSON', uris = ['gs://telco-landing/cdr/*.json']);
-- Continuous load (Snowpipe): Pub/Sub BigQuery subscription, or Storage Transfer + BigQuery Data Transfer Service.

-- External table over Parquet
create or replace external table `my-project.raw.ext_tower_log`
options (format = 'PARQUET', uris = ['gs://telco-landing/tower/*.parquet']);

-- Streams -> change history (read with CHANGES(); window = time travel)
alter table `my-project.raw.cdr`         set options (enable_change_history = true);
alter table `my-project.raw.subscribers` set options (enable_change_history = true);

create or replace table `my-project.audit.dbt_run_log` (
    invocation_id string, node_id string, status string, exec_seconds float64, logged_at datetime
);
create or replace table `my-project.audit.cdr_hourly_counts` (hour_ts datetime, c int64);

-- Tasks -> scheduled query. Hourly count of new rows (CHANGES needs an end time at least 10 min old):
--   bq mk --transfer_config --data_source=scheduled_query --schedule='every 1 hours' \
--     --display_name='cdr_hourly' --params='{"query":"insert into audit.cdr_hourly_counts select datetime_trunc(loaded_at, hour), count(*) from raw.cdr where loaded_at >= datetime_sub(current_datetime(), interval 1 hour) group by 1"}'
-- Task graph + EXECUTE DBT PROJECT -> Cloud Composer / Workflows / dbt Cloud job running `dbt build --select tag:marts`.

-- UDFs
create or replace function `my-project.raw.normalize_msisdn`(m string) returns string as (
    regexp_replace(m, r'[^0-9+]', '')
);

create or replace function `my-project.raw.bytes_to_gb_js`(b float64) returns float64
language js as r"""
    return b / 1073741824;
""";

-- Python UDF -> SQL
create or replace function `my-project.raw.risk_bucket`(score float64) returns string as (
    case when score > 0.7 then 'HIGH' when score > 0.4 then 'MEDIUM' else 'LOW' end
);

-- Procedure
create or replace procedure `my-project.raw.sp_archive_cdr`(days int64)
begin
    delete from `my-project.raw.cdr`
    where loaded_at < datetime_sub(current_datetime(), interval days day);
end;

-- Materialized view
create materialized view if not exists `my-project.raw.mv_cdr_daily` as
    select date(loaded_at) as d, call_type, count(*) as c
    from `my-project.raw.cdr`
    group by 1, 2;

-- Share -> Analytics Hub exchange + listing (console / API), not SQL.

-- Grants (Snowflake: grant select on all/future tables). Dataset-level IAM covers future tables.
grant `roles/bigquery.dataViewer` on schema `my-project.marts`
    to 'group:analysts@example.com';
