-- fails if balance != total - paid
select invoice_id
from {{ ref('fct_billing') }}
where abs(balance - (total - paid)) > 0.01
