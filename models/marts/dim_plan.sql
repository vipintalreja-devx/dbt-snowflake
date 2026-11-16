select
    plan_id,
    plan_name,
    monthly_fee,
    data_gb,
    voice_min,
    sms_count,
    valid_from,
    valid_to,
    valid_to = '9999-12-31'::date as is_current,
    case
        when monthly_fee >= 50 then 'PREMIUM'
        when monthly_fee >= 20 then 'STANDARD'
        else 'BASIC'
    end as plan_tier
from {{ ref('stg_plans') }}
