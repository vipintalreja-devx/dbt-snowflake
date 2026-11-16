-- Snowflake dynamic table (5 min lag) -> plain view (always fresh, computed per query).
-- A BigQuery materialized view is not used: it must read a base table (not a view)
-- and cannot use current_timestamp() filters.
{{ config(materialized='view') }}

select
    cell_id,
    datetime_trunc(start_ts, minute) as minute_ts,
    count(*)                         as events,
    sum(bytes_used)                  as bytes
from {{ ref('stg_cdr') }}
where start_ts >= datetime_sub(current_datetime(), interval 24 hour)
group by 1, 2
