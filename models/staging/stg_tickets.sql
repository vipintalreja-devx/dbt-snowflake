select
    ticket_id,
    subscriber_id,
    opened_at,
    closed_at,
    lower(category)                                                                   as category,
    datetime_diff(coalesce(closed_at, current_datetime()), opened_at, hour)           as hours_open
from {{ source('raw', 'tickets') }}
