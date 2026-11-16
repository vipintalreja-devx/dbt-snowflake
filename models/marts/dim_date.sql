{{ config(materialized='table', transient=false) }}

with spine as (
    {{ date_spine_sf(var('start_date'), 3650) }}
)
select
    date_day,
    year(date_day)                      as year_num,
    quarter(date_day)                   as quarter_num,
    month(date_day)                     as month_num,
    monthname(date_day)                 as month_name,
    dayofweekiso(date_day)              as iso_dow,
    dayname(date_day)                   as day_name,
    iff(dayofweekiso(date_day) >= 6, true, false) as is_weekend,
    last_day(date_day, 'month')         as month_end,
    to_char(date_day, 'YYYYMM')         as year_month
from spine
