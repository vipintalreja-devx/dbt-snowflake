select
    cell_id,
    date_trunc('hour', event_ts)                                      as hour_ts,
    count(distinct event_id)                                          as events,
    median(iff(metric_name = 'latency_ms', metric_value, null))       as latency_p50,
    approx_percentile(iff(metric_name = 'latency_ms', metric_value, null), 0.95) as latency_p95,
    avg(iff(metric_name = 'packet_loss_pct', metric_value, null))     as avg_packet_loss,
    max_by(event_type, severity)                                      as worst_event_type,
    array_agg(distinct event_type) within group (order by event_type) as event_types
from {{ ref('stg_network_events') }}
group by 1, 2
