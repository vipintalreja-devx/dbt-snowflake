select
    subscriber_id,
    msisdn,
    full_name,
    {{ mask_pii('email') }}                                    as email_hash,
    dob,
    date_diff(current_date(), dob, year)                       as age,
    activation_date,
    upper(status)                                              as status,
    plan_id,
    json_value(address, '$.city')                              as city,
    json_value(address, '$.state')                             as state,
    safe_cast(json_value(address, '$.geo.lat') as float64)     as lat,
    safe_cast(json_value(address, '$.geo.lon') as float64)     as lon,
    updated_at
from {{ source('raw', 'subscribers') }}
