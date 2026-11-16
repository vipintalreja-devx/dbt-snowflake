{{ config(materialized='table') }}

with spine as (
    {{ date_spine_sf(var('start_date'), 3650) }}
)
select
    date_day,
    extract(year from date_day)                              as year_num,
    extract(quarter from date_day)                           as quarter_num,
    extract(month from date_day)                             as month_num,
    format_date('%B', date_day)                              as month_name,
    mod(extract(dayofweek from date_day) + 5, 7) + 1         as iso_dow,   -- Mon=1 .. Sun=7
    format_date('%A', date_day)                              as day_name,
    extract(dayofweek from date_day) in (1, 7)               as is_weekend,
    last_day(date_day, month)                                as month_end,
    format_date('%Y%m', date_day)                            as year_month
from spine
