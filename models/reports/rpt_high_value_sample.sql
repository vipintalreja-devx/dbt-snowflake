-- SAMPLE -> TABLESAMPLE SYSTEM, TOP -> LIMIT, AT(OFFSET) -> FOR SYSTEM_TIME AS OF, ILIKE -> LOWER + LIKE
with b as (
    select * from {{ ref('fct_billing') }} tablesample system (10 percent)
),

s as (
    select * from {{ ref('dim_subscriber') }}
    for system_time as of timestamp_sub(current_timestamp(), interval 1 hour)
)

select s.subscriber_id, s.full_name, s.plan_name, b.total
from b
join s using (subscriber_id)
where b.total > {{ var('high_value_threshold') }}
  and lower(s.plan_name) like '%premium%'
order by b.total desc
limit 100
