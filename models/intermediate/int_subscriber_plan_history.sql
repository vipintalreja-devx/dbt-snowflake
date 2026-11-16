with base as (
    select
        subscriber_id,
        plan_id,
        dbt_valid_from                                                  as valid_from,
        coalesce(dbt_valid_to, datetime '9999-12-31 00:00:00')          as valid_to,
        lag(plan_id) over (partition by subscriber_id order by dbt_valid_from) as prev_plan_id
    from {{ ref('snap_subscribers') }}
)

select
    *,
    -- replaces CONDITIONAL_CHANGE_EVENT: running count of plan changes
    sum(if(prev_plan_id is not null and plan_id != prev_plan_id, 1, 0))
        over (partition by subscriber_id order by valid_from
              rows between unbounded preceding and current row)         as change_seq
from base
