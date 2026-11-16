{{
    config(
        materialized='incremental',
        unique_key='invoice_id',
        incremental_strategy='merge',
        merge_exclude_columns=['first_loaded_at']
    )
}}

with inv as (
    select * from {{ ref('stg_invoices') }}
    {% if is_incremental() %}
    where updated_at > (select max(updated_at) from {{ this }})
    {% endif %}
),

pay as (
    select invoice_id, sum(amount) as paid, max(paid_at) as last_paid_at
    from {{ ref('stg_payments') }}
    group by 1
)

select
    inv.invoice_id,
    inv.subscriber_id,
    inv.period_start,
    inv.period_end,
    inv.amount,
    inv.tax,
    inv.amount + inv.tax                              as total,
    coalesce(pay.paid, 0)                             as paid,
    inv.amount + inv.tax - coalesce(pay.paid, 0)      as balance,
    {{ safe_divide('inv.tax', 'inv.amount') }}        as tax_rate,
    datediff(day, inv.period_end, pay.last_paid_at::date) as days_to_pay,
    case
        when pay.paid >= inv.amount + inv.tax then 'PAID'
        when datediff(day, inv.period_end, current_date()) > 60 then '60+'
        when datediff(day, inv.period_end, current_date()) > 30 then '30-60'
        else 'CURRENT'
    end                                               as aging_bucket,
    inv.updated_at,
    current_timestamp()                               as first_loaded_at
from inv
left join pay using (invoice_id)
