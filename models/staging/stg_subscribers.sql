select
    subscriber_id,
    msisdn,
    full_name,
    {{ mask_pii('email') }}                  as email_hash,
    dob,
    datediff(year, dob, current_date())      as age,
    activation_date,
    upper(status)                            as status,
    plan_id,
    address:city::string                     as city,
    address:state::string                    as state,
    address:geo.lat::float                   as lat,
    address:geo.lon::float                   as lon,
    updated_at
from {{ source('raw', 'subscribers') }}
