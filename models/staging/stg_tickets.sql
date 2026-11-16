select
    ticket_id,
    subscriber_id,
    opened_at,
    closed_at,
    lower(category)                                      as category,
    datediff(hour, opened_at, coalesce(closed_at, current_timestamp())) as hours_open
from {{ source('raw', 'tickets') }}
