with usg as (
    select
        msisdn,
        avg(data_mb)                                       as avg_daily_mb,
        sum(roaming_events)                                as roaming_events_90d,
        date_diff(current_date(), max(usage_date), day)    as days_since_last_use
    from {{ ref('fct_usage_daily') }}
    where usage_date >= date_sub(current_date(), interval 90 day)
    group by 1
),

tix as (
    select
        subscriber_id,
        count(*)                                                       as tickets_90d,
        string_agg(distinct category, ', ' order by category)          as ticket_categories,
        array_agg(struct(ticket_id as id, category as cat, hours_open as hrs)
                  order by opened_at)                                  as ticket_detail
    from {{ ref('stg_tickets') }}
    where opened_at >= datetime_sub(current_datetime(), interval 90 day)
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
    safe_divide(coalesce(u.avg_daily_mb, 0),
                sum(coalesce(u.avg_daily_mb, 0)) over (partition by s.plan_tier)) as share_of_tier_data,
    to_json(struct(
        s.tenure_months                    as tenure,
        coalesce(t.tickets_90d, 0)         as tickets,
        coalesce(u.roaming_events_90d, 0)  as roaming
    ))                                     as feature_vector
from {{ ref('dim_subscriber') }} s
left join usg u on s.msisdn = u.msisdn
left join tix t on s.subscriber_id = t.subscriber_id
left join bill b on s.subscriber_id = b.subscriber_id
