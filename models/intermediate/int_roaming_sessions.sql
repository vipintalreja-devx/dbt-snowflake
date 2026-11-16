-- Runs of consecutive roaming DATA events per subscriber (Snowflake MATCH_RECOGNIZE)
select *
from {{ ref('int_cdr_enriched') }}
    match_recognize(
        partition by msisdn
        order by start_ts
        measures
            match_number()        as session_id,
            first(start_ts)       as session_start,
            last(start_ts)        as session_end,
            count(*)              as events,
            sum(bytes_used)       as total_bytes
        one row per match
        after match skip past last row
        pattern (r+)
        define r as call_type = 'DATA' and is_roaming
    )
