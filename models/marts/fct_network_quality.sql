{{
    config(
        partition_by={'field': 'hour_ts', 'data_type': 'datetime', 'granularity': 'day'},
        cluster_by=['cell_id']
    )
}}

-- NOTE: latency_p50 is approximate here (Snowflake MEDIAN is exact)
select
    cell_id,
    datetime_trunc(event_ts, hour)                                                  as hour_ts,
    count(distinct event_id)                                                        as events,
    approx_quantiles(if(metric_name = 'latency_ms', metric_value, null), 100)[offset(50)] as latency_p50,
    approx_quantiles(if(metric_name = 'latency_ms', metric_value, null), 100)[offset(95)] as latency_p95,
    avg(if(metric_name = 'packet_loss_pct', metric_value, null))                    as avg_packet_loss,
    array_agg(event_type ignore nulls order by severity desc limit 1)[safe_offset(0)] as worst_event_type,
    array_agg(distinct event_type ignore nulls order by event_type)                 as event_types
from {{ ref('stg_network_events') }}
group by 1, 2
