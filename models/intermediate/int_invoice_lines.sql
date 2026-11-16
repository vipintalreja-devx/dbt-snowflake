select
    i.invoice_id,
    i.subscriber_id,
    line_no,
    json_value(l, '$.item')                             as item,
    safe_cast(json_value(l, '$.qty') as int64)          as qty,
    {{ cents_to_dollars("json_value(l, '$.amount_cents')") }} as line_amount
from {{ ref('stg_invoices') }} i,
     unnest(json_query_array(i.lines)) as l with offset as line_no
