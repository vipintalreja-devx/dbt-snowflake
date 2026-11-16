select
    e.event_id,
    e.cell_id,
    e.event_ts::timestamp_ntz           as event_ts,
    e.event_json:type::string           as event_type,
    e.event_json:severity::int          as severity,
    f.value:name::string                as metric_name,
    f.value:val::float                  as metric_value
from {{ source('raw', 'network_events') }} e,
     lateral flatten(input => e.event_json:metrics, outer => true) f
