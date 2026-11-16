select
    i.invoice_id,
    i.subscriber_id,
    l.index                                      as line_no,
    l.value:item::string                         as item,
    l.value:qty::number                          as qty,
    {{ cents_to_dollars('l.value:amount_cents') }} as line_amount
from {{ ref('stg_invoices') }} i,
     table(flatten(input => i.lines)) l
