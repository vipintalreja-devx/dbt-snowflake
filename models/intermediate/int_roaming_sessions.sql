-- Runs of consecutive roaming DATA events per subscriber.
-- MATCH_RECOGNIZE has no BigQuery equivalent: rewritten as gaps-and-islands.
with ordered as (
    select
        msisdn, cdr_id, start_ts, bytes_used,
        (call_type = 'DATA' and ifnull(is_roaming, false))                    as is_r,
        row_number() over (partition by msisdn order by start_ts, cdr_id)     as rn
    from {{ ref('int_cdr_enriched') }}
),

flagged as (
    select
        *,
        rn - row_number() over (partition by msisdn, is_r order by start_ts, cdr_id) as grp
    from ordered
)

select
    msisdn,
    row_number() over (partition by msisdn order by min(start_ts)) as session_id,
    min(start_ts)                                                  as session_start,
    max(start_ts)                                                  as session_end,
    count(*)                                                       as events,
    sum(bytes_used)                                                as total_bytes
from flagged
where is_r
group by msisdn, grp
