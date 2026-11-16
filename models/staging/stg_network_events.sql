select
    e.event_id,
    e.cell_id,
    cast(e.event_ts as datetime)                              as event_ts,
    json_value(e.event_json, '$.type')                        as event_type,
    safe_cast(json_value(e.event_json, '$.severity') as int64) as severity,
    json_value(f, '$.name')                                   as metric_name,
    safe_cast(json_value(f, '$.val') as float64)              as metric_value
from {{ source('raw', 'network_events') }} e
left join unnest(json_query_array(e.event_json, '$.metrics')) as f
