{{
    config(
        materialized='dynamic_table',
        snowflake_warehouse='TRANSFORM_WH',
        target_lag='5 minutes',
        on_configuration_change='apply'
    )
}}

select
    cell_id,
    date_trunc('minute', start_ts) as minute_ts,
    count(*)                       as events,
    sum(bytes_used)                as bytes
from {{ ref('stg_cdr') }}
where start_ts >= dateadd(hour, -24, current_timestamp())
group by 1, 2
