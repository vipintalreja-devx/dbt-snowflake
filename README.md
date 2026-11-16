# dbt-snowflake

Sample dbt models for a telco database. The models were written for Snowflake and then translated to BigQuery (see `TRANSLATION_REPORT.md`). The BigQuery versions are the ones currently in `models/`. The Snowflake snippets below show what the same model looks like on Snowflake.

## dbt on Snowflake vs dbt on BigQuery

dbt itself (`ref`, `source`, tests, snapshots, Jinja, docs) works the same on both. The differences come from the warehouse underneath: the SQL dialect, how data is stored and billed, and which materialization options the adapter exposes.

| Area | Snowflake (`dbt-snowflake`) | BigQuery (`dbt-bigquery`) |
|---|---|---|
| Compute model | Virtual warehouses you size and pause. Billed per second of warehouse uptime. | Serverless. Billed per bytes scanned (on-demand) or per slot. No warehouse to manage. |
| Namespace | `database.schema.table` | `project.dataset.table`. `schema` in dbt means a BigQuery dataset. |
| Performance tuning | `cluster_by` (clustering keys). Micro-partitions are automatic. | `partition_by` plus `cluster_by`. Partitioning is explicit and controls how much data a query scans. |
| Incremental strategies | `merge` (default), `delete+insert`, `append` | `merge`, `insert_overwrite` (by partition), `microbatch` |
| Semi-structured data | `VARIANT`, `col:a.b::string`, `LATERAL FLATTEN` | `JSON` or `STRING`, `JSON_VALUE`, `UNNEST` |
| Connection config | account, user, role, warehouse, key pair | project, dataset, location, OAuth or service account |
| Access control | `GRANT` to roles, secure views, masking policies | IAM roles, authorized views, policy tags |
| Warehouse-only features | Dynamic tables, streams, tasks, `MATCH_RECOGNIZE`, time travel up to 90 days | Materialized views with limits, `enable_change_history`, time travel up to 7 days |
| Cost guardrail | Warehouse size and auto-suspend | `maximum_bytes_billed` in the profile |

The practical consequence: on Snowflake you tune by choosing a warehouse size, and on BigQuery you tune by limiting how many bytes each query reads (partition filters, clustering, selecting fewer columns).

## Connection profile

Snowflake:

```yaml
telco:
  target: dev
  outputs:
    dev:
      type: snowflake
      account: "{{ env_var('SNOWFLAKE_ACCOUNT') }}"
      user: "{{ env_var('SNOWFLAKE_USER') }}"
      private_key_path: "{{ env_var('SNOWFLAKE_KEY') }}"
      role: TRANSFORMER
      warehouse: TRANSFORM_WH
      database: TELCO
      schema: dbt_dev
      threads: 4
```

BigQuery (`profiles.yml.example`):

```yaml
telco:
  target: dev
  outputs:
    dev:
      type: bigquery
      method: oauth
      project: "{{ env_var('GCP_PROJECT_DEV') }}"
      dataset: dbt_dev
      location: asia-south1
      threads: 4
      maximum_bytes_billed: 50000000000
```

Snowflake needs a `warehouse` and `role`. BigQuery needs a `location` (it must match the data) and offers `maximum_bytes_billed` as a cost cap.

## Code differences by model

### 1. `stg_cdr`: JSON paths, parsing and null handling

Snowflake:

```sql
select
    cdr_id,
    upper(call_type)                                         as call_type,
    try_to_timestamp_ntz(start_ts_raw, 'YYYY-MM-DD HH24:MI:SS') as start_ts,
    zeroifnull(duration_sec)                                 as duration_sec,
    raw_payload:imei::string                                 as imei,
    raw_payload:network.rat::string                          as rat,
    regexp_substr(called_number, '^\\+?(\\d{1,3})', 1, 1, 'e') as country_code
from {{ source('raw', 'cdr') }}
```

BigQuery:

```sql
select
    cdr_id,
    upper(call_type)                                         as call_type,
    safe.parse_datetime('%Y-%m-%d %H:%M:%S', start_ts_raw)   as start_ts,
    ifnull(duration_sec, 0)                                  as duration_sec,
    json_value(raw_payload, '$.imei')                        as imei,
    json_value(raw_payload, '$.network.rat')                 as rat,
    regexp_extract(called_number, r'^\+?(\d{1,3})')          as country_code
from {{ source('raw', 'cdr') }}
```

- Snowflake reads JSON with the colon path and a `::` cast. BigQuery uses `JSON_VALUE` with a `$.` path.
- `TRY_TO_...` becomes the `SAFE.` prefix, which returns NULL instead of failing.
- Date format codes differ: `YYYY-MM-DD HH24:MI:SS` vs `%Y-%m-%d %H:%M:%S`.
- Regex on BigQuery uses a raw string (`r'...'`), so backslashes are not doubled.

### 2. `int_cdr_enriched`: incremental table with partitioning

Snowflake:

```sql
{{ config(
    materialized='incremental',
    unique_key='cdr_id',
    incremental_strategy='merge',
    cluster_by=['start_date', 'msisdn']
) }}

select ...,
    md5_binary(concat_ws('|', d.cdr_id, d.msisdn)) as cdr_key
from dedup d
-- dedup uses: qualify row_number() over (...) = 1
```

BigQuery:

```sql
{{ config(
    materialized='incremental',
    unique_key='cdr_id',
    incremental_strategy='merge',
    partition_by={'field': 'start_date', 'data_type': 'date'},
    cluster_by=['msisdn']
) }}

dedup as (
    select * from src
    where true  -- QUALIFY needs a WHERE/GROUP BY/HAVING on older BigQuery
    qualify row_number() over (partition by cdr_id order by loaded_at desc) = 1
)
...
{{ hash_key(['d.cdr_id', 'd.msisdn']) }} as cdr_key
```

- Snowflake only needs `cluster_by`. BigQuery adds `partition_by`, so queries that filter on `start_date` scan less data.
- `QUALIFY` exists on both, but BigQuery requires a `WHERE`, `GROUP BY` or `HAVING` next to it.
- Snowflake `MD5_BINARY` returns binary. BigQuery has no `CONCAT_WS`, so the `hash_key` macro uses `to_hex(md5(array_to_string(...)))`. The key values are hex text, so they will not match Snowflake keys.
- The macro uses `adapter.dispatch`, so one call works on both warehouses (`snowflake__hash_key` and `bigquery__hash_key`).

### 3. `fct_usage_daily`: incremental strategy

Snowflake:

```sql
{{ config(
    materialized='incremental',
    incremental_strategy='delete+insert',
    unique_key=['msisdn', 'usage_date'],
    snowflake_warehouse='TRANSFORM_XL'
) }}

select msisdn, start_date as usage_date,
       count_if(call_type = 'VOICE') as calls,
       approx_count_distinct(cell_id) as distinct_cells
from {{ ref('int_cdr_enriched') }}
{% if is_incremental() %}
where start_date >= dateadd(day, -{{ var('lookback_days') }}, current_date)
{% endif %}
group by 1, 2
```

BigQuery:

```sql
{% set partitions_to_replace = [] %}
{% for i in range(0, var('lookback_days') + 1) %}
    {% do partitions_to_replace.append('date_sub(current_date(), interval ' ~ i ~ ' day)') %}
{% endfor %}

{{ config(
    materialized='incremental',
    incremental_strategy='insert_overwrite',
    partition_by={'field': 'usage_date', 'data_type': 'date'},
    partitions=partitions_to_replace,
    cluster_by=['msisdn']
) }}

select msisdn, start_date as usage_date,
       countif(call_type = 'VOICE') as calls,
       approx_count_distinct(cell_id) as distinct_cells
from {{ ref('int_cdr_enriched') }}
{% if is_incremental() %}
where start_date >= date_sub(current_date(), interval {{ var('lookback_days') }} day)
{% endif %}
group by 1, 2
```

- Snowflake deletes the matching keys and inserts the new rows. BigQuery has no `delete+insert`, so it replaces whole date partitions with `insert_overwrite`.
- `insert_overwrite` is cheaper on BigQuery because it avoids a full-table merge scan. The `partitions` list must cover the lookback window, or old rows stay stale.
- `snowflake_warehouse` (pick a bigger warehouse for one model) has no BigQuery equivalent.
- `COUNT_IF` becomes `COUNTIF`, and `DATEADD(day, -n, d)` becomes `DATE_SUB(d, INTERVAL n DAY)`.

### 4. `fct_billing`: date functions and safe division

Snowflake:

```sql
div0null(inv.tax, inv.amount)                       as tax_rate,
datediff(day, inv.period_end, pay.last_paid_at)     as days_to_pay,
case when datediff(day, inv.period_end, current_date) > 60 then '60+' ... end
```

BigQuery:

```sql
{{ safe_divide('inv.tax', 'inv.amount') }}                  as tax_rate,
date_diff(date(pay.last_paid_at), inv.period_end, day)      as days_to_pay,
case when date_diff(current_date(), inv.period_end, day) > 60 then '60+' ... end
```

- Snowflake `DATEDIFF(unit, start, end)` takes the start date first. BigQuery `DATE_DIFF(end, start, unit)` takes the end date first, so the result sign flips if you forget to swap.
- `DIV0NULL` becomes `SAFE_DIVIDE`. Both return NULL on a zero divisor, but the macro hides the difference.
- BigQuery is stricter about types. `DATE_DIFF` needs two DATE values, so a timestamp has to be wrapped in `date(...)`.

### 5. `int_roaming_sessions`: a feature with no equivalent

Snowflake uses `MATCH_RECOGNIZE` to find runs of consecutive roaming data events:

```sql
select * from {{ ref('int_cdr_enriched') }}
match_recognize (
    partition by msisdn
    order by start_ts
    measures match_number() as session_id,
             min(start_ts) as session_start,
             max(start_ts) as session_end,
             count(*)      as events
    pattern (r+)
    define r as call_type = 'DATA' and is_roaming
)
```

BigQuery rebuilds it as gaps-and-islands with two `ROW_NUMBER` calls:

```sql
with ordered as (
    select msisdn, cdr_id, start_ts, bytes_used,
           (call_type = 'DATA' and ifnull(is_roaming, false)) as is_r,
           row_number() over (partition by msisdn order by start_ts, cdr_id) as rn
    from {{ ref('int_cdr_enriched') }}
),
flagged as (
    select *,
           rn - row_number() over (partition by msisdn, is_r order by start_ts, cdr_id) as grp
    from ordered
)
select msisdn, min(start_ts) as session_start, max(start_ts) as session_end, count(*) as events
from flagged
where is_r
group by msisdn, grp
```

Rows in the same run share the same `rn - row_number()` value, so grouping by it gives one row per session. Ties on equal timestamps are broken with `cdr_id`.

### 6. `dt_realtime_usage`: a materialization that does not exist

Snowflake:

```sql
{{ config(
    materialized='dynamic_table',
    target_lag='5 minutes',
    snowflake_warehouse='TRANSFORM_WH'
) }}

select cell_id, date_trunc('minute', start_ts) as minute_ts,
       count(*) as events, sum(bytes_used) as bytes
from {{ ref('stg_cdr') }}
where start_ts >= dateadd(hour, -24, current_timestamp())
group by 1, 2
```

BigQuery:

```sql
{{ config(materialized='view') }}

select cell_id, datetime_trunc(start_ts, minute) as minute_ts,
       count(*) as events, sum(bytes_used) as bytes
from {{ ref('stg_cdr') }}
where start_ts >= datetime_sub(current_datetime(), interval 24 hour)
group by 1, 2
```

Snowflake keeps the result refreshed within the target lag. BigQuery materialized views cannot read from a view or use `current_timestamp()` filters, so the model becomes a plain view that recomputes on every query. If query cost matters, switch to a scheduled table.

## Other common function mappings

| Snowflake | BigQuery |
|---|---|
| `IFF(a, b, c)` | `IF(a, b, c)` |
| `LISTAGG(x, ',')` | `STRING_AGG(x, ',')` |
| `OBJECT_CONSTRUCT(...)` | `TO_JSON(STRUCT(...))` |
| `MEDIAN(x)` | `APPROX_QUANTILES(x, 2)[OFFSET(1)]` (approximate) |
| `LATERAL FLATTEN(input => col)` | `CROSS JOIN UNNEST(JSON_QUERY_ARRAY(col))` |
| `GENERATOR(ROWCOUNT => n)` | `GENERATE_DATE_ARRAY(start, end)` |
| `SAMPLE (10)` | `TABLESAMPLE SYSTEM (10 PERCENT)` |
| `AT(OFFSET => -3600)` | `FOR SYSTEM_TIME AS OF TIMESTAMP_SUB(...)` |
| `ILIKE` | `LOWER(x) LIKE LOWER(y)` |

## More detail

`TRANSLATION_REPORT.md` lists every object, its status and the risks. The Snowflake snippets above are illustrative and were not run in this repo. The BigQuery code has not been compiled or run against BigQuery either.
