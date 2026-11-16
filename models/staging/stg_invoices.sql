select
    invoice_id,
    subscriber_id,
    period_start,
    period_end,
    {{ cents_to_dollars('amount_cents') }}  as amount,
    {{ cents_to_dollars('tax_cents') }}     as tax,
    upper(status)                           as status,
    lines,
    updated_at
from {{ source('raw', 'invoices') }}
