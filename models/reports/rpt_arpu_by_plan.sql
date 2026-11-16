with base as (
    select
        date_trunc(b.period_start, month) as month,
        s.plan_name,
        b.subscriber_id,
        b.total
    from {{ ref('fct_billing') }} b
    join {{ ref('dim_subscriber') }} s using (subscriber_id)
)

select
    month,
    plan_name,
    -- Snowflake GROUPING(a, b) bitmask rebuilt from two single-arg calls
    grouping(month) * 2 + grouping(plan_name)               as grouping_id,
    count(distinct subscriber_id)                           as billed_subs,
    sum(total)                                              as revenue,
    {{ safe_divide('sum(total)', 'count(distinct subscriber_id)') }} as arpu
from base
group by rollup (month, plan_name)
