select
    subscriber_id,
    plan_id,
    dbt_valid_from                                                  as valid_from,
    coalesce(dbt_valid_to, '9999-12-31'::timestamp_ntz)             as valid_to,
    lag(plan_id) over (partition by subscriber_id order by dbt_valid_from) as prev_plan_id,
    conditional_change_event(plan_id)
        over (partition by subscriber_id order by dbt_valid_from)   as change_seq
from {{ ref('snap_subscribers') }}
