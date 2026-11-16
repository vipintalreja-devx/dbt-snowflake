-- BigQuery PIVOT: no column alias list, so rename in an outer select
select
    state,
    ACTIVE    as active,
    SUSPENDED as suspended,
    CHURNED   as churned
from (
    select state, status, subscriber_id from {{ ref('dim_subscriber') }}
)
pivot (count(subscriber_id) for status in ('ACTIVE', 'SUSPENDED', 'CHURNED'))
order by state
