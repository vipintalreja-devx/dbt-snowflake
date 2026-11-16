-- native Snowflake PIVOT
select *
from (
    select state, status, subscriber_id from {{ ref('dim_subscriber') }}
)
pivot (count(subscriber_id) for status in ('ACTIVE', 'SUSPENDED', 'CHURNED'))
    as p (state, active, suspended, churned)
order by state
