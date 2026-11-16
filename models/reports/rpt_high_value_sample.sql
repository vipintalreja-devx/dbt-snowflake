-- Snowflake SAMPLE, TOP, time travel (AT) and ILIKE
select top 100 s.subscriber_id, s.full_name, s.plan_name, b.total
from {{ ref('fct_billing') }} sample (10) b
join {{ ref('dim_subscriber') }} at (offset => -3600) s using (subscriber_id)
where b.total > {{ var('high_value_threshold') }}
  and s.plan_name ilike '%premium%'
order by b.total desc
