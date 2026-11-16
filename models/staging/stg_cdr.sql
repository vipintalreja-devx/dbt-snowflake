{{ config(materialized='view') }}

select
    cdr_id,
    msisdn,
    called_number,
    upper(call_type)                                              as call_type,
    try_to_timestamp_ntz(start_ts_raw, 'YYYY-MM-DD HH24:MI:SS')   as start_ts,
    zeroifnull(duration_sec)                                      as duration_sec,
    zeroifnull(bytes_used)                                        as bytes_used,
    cell_id,
    roaming_flag::boolean                                         as is_roaming,
    raw_payload:imei::string                                      as imei,
    raw_payload:network.rat::string                               as rat,
    regexp_substr(called_number, '^\\+?(\\d{1,3})', 1, 1, 'e')    as country_code,
    loaded_at
from {{ source('raw', 'cdr') }}
where cdr_id is not null
