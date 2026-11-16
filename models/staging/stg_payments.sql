select
    payment_id,
    invoice_id,
    paid_at::timestamp_ntz                  as paid_at,
    {{ cents_to_dollars('amount_cents') }}  as amount,
    lower(method)                           as method
from {{ source('raw', 'payments') }}
