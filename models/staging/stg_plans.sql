select
    plan_id,
    initcap(plan_name)                                   as plan_name,
    {{ cents_to_dollars('monthly_fee_cents') }}          as monthly_fee,
    data_gb,
    voice_min,
    sms_count,
    valid_from,
    coalesce(valid_to, '9999-12-31'::date)               as valid_to
from {{ source('raw', 'plans') }}
