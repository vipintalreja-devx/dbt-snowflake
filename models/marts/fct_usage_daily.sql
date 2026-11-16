{# delete+insert is not supported on BigQuery: use insert_overwrite on date partitions #}
{% set partitions_to_replace = [] %}
{% for i in range(0, var('lookback_days') + 1) %}
    {% do partitions_to_replace.append('date_sub(current_date(), interval ' ~ i ~ ' day)') %}
{% endfor %}

{{
    config(
        materialized='incremental',
        incremental_strategy='insert_overwrite',
        partition_by={'field': 'usage_date', 'data_type': 'date'},
        partitions=partitions_to_replace,
        cluster_by=['msisdn']
    )
}}

select
    msisdn,
    start_date                                          as usage_date,
    countif(call_type = 'VOICE')                        as calls,
    sum(if(call_type = 'VOICE', duration_sec, 0)) / 60  as voice_min,
    countif(call_type = 'SMS')                          as sms,
    sum(ifnull(mb_used, 0))                             as data_mb,
    countif(is_roaming)                                 as roaming_events,
    approx_count_distinct(cell_id)                      as distinct_cells
from {{ ref('int_cdr_enriched') }}
{% if is_incremental() %}
where start_date >= date_sub(current_date(), interval {{ var('lookback_days') }} day)
{% endif %}
group by 1, 2
