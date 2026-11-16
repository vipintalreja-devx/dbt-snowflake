with usage as (
    select
        msisdn,
        avg(data_mb)                                  as avg_daily_mb,
        sum(roaming_events)                           as roaming_events_90d,
        datediff(day, max(usage_date), current_date()) as days_since_last_use
    from {{ ref('fct_usage_daily') }}
    where usage_date >= dateadd(day, -90, current_date())
    group by 1
),

tix as (
    select
        subscriber_id,
        count(*)                                                  as tickets_90d,
        listagg(distinct category, ', ') within group (order by category) as ticket_categories,
        array_agg(object_construct('id', ticket_id, 'cat', category, 'hrs', hours_open))
            within group (order by opened_at)                     as ticket_detail
    from {{ ref('stg_tickets') }}
    where opened_at >= dateadd(day, -90, current_date())
    group by 1
),

bill as (
    select subscriber_id, avg(days_to_pay) as avg_days_to_pay, sum(balance) as open_balance
    from {{ ref('fct_billing') }}
    group by 1
)

select
    s.subscriber_id,
    s.msisdn,
    s.tenure_months,
    s.plan_tier,
    coalesce(u.avg_daily_mb, 0)           as avg_daily_mb,
    coalesce(u.days_since_last_use, 999)  as days_since_last_use,
    coalesce(t.tickets_90d, 0)            as tickets_90d,
    t.ticket_categories,
    t.ticket_detail,
    b.avg_days_to_pay,
    b.open_balance,
    ratio_to_report(coalesce(u.avg_daily_mb, 0)) over (partition by s.plan_tier) as share_of_tier_data,
    object_construct(
        'tenure', s.tenure_months,
        'tickets', coalesce(t.tickets_90d, 0),
        'roaming', coalesce(u.roaming_events_90d, 0)
    )                                     as feature_vector
from {{ ref('dim_subscriber') }} s
left join usage u on s.msisdn = u.msisdn
left join tix t on s.subscriber_id = t.subscriber_id
left join bill b on s.subscriber_id = b.subscriber_id
