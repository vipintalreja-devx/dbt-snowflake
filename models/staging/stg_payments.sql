select
    payment_id,
    invoice_id,
    cast(paid_at as datetime)               as paid_at,
    {{ cents_to_dollars('amount_cents') }}  as amount,
    lower(method)                           as method
from {{ source('raw', 'payments') }}
