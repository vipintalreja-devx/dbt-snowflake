{{ config(cluster_by=['state', 'status']) }}

select
    s.subscriber_id,
    s.msisdn,
    s.full_name,
    s.email_hash,
    s.age,
    s.city,
    s.state,
    s.status,
    s.activation_date,
    date_diff(current_date(), s.activation_date, month) as tenure_months,
    p.plan_id,
    p.plan_name,
    p.plan_tier,
    p.monthly_fee,
    h.change_seq                                        as plan_change_count,
    h.prev_plan_id
from {{ ref('stg_subscribers') }} s
left join {{ ref('dim_plan') }} p
    on s.plan_id = p.plan_id and p.is_current
left join {{ ref('int_subscriber_plan_history') }} h
    on s.subscriber_id = h.subscriber_id and h.valid_to = datetime '9999-12-31 00:00:00'
