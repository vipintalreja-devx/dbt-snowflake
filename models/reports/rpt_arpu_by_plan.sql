select
    date_trunc('month', b.period_start)         as month,
    s.plan_name,
    grouping(date_trunc('month', b.period_start), s.plan_name) as grouping_id,
    count(distinct b.subscriber_id)             as billed_subs,
    sum(b.total)                                as revenue,
    {{ safe_divide('sum(b.total)', 'count(distinct b.subscriber_id)') }} as arpu
from {{ ref('fct_billing') }} b
join {{ ref('dim_subscriber') }} s using (subscriber_id)
group by rollup (date_trunc('month', b.period_start), s.plan_name)
