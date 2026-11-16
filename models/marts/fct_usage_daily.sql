{{
    config(
        materialized='incremental',
        unique_key=['msisdn', 'usage_date'],
        incremental_strategy='delete+insert',
        cluster_by=['usage_date'],
        snowflake_warehouse='TRANSFORM_WH_L'
    )
}}

select
    msisdn,
    start_date                                         as usage_date,
    count_if(call_type = 'VOICE')                      as calls,
    sum(iff(call_type = 'VOICE', duration_sec, 0)) / 60 as voice_min,
    count_if(call_type = 'SMS')                        as sms,
    sum(coalesce(mb_used, 0))                          as data_mb,
    count_if(is_roaming)                               as roaming_events,
    approx_count_distinct(cell_id)                     as distinct_cells
from {{ ref('int_cdr_enriched') }}
{% if is_incremental() %}
where start_date >= dateadd(day, -{{ var('lookback_days') }}, current_date())
{% endif %}
group by 1, 2
