{{ config(materialized='view') }}

select
    cdr_id,
    msisdn,
    called_number,
    upper(call_type)                                           as call_type,
    safe.parse_datetime('%Y-%m-%d %H:%M:%S', start_ts_raw)     as start_ts,
    ifnull(duration_sec, 0)                                    as duration_sec,
    ifnull(bytes_used, 0)                                      as bytes_used,
    cell_id,
    safe_cast(roaming_flag as bool)                            as is_roaming,
    json_value(raw_payload, '$.imei')                          as imei,
    json_value(raw_payload, '$.network.rat')                   as rat,
    regexp_extract(called_number, r'^\+?(\d{1,3})')            as country_code,
    loaded_at
from {{ source('raw', 'cdr') }}
where cdr_id is not null
