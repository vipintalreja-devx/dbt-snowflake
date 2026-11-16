-- Snowpark Python model rewritten in SQL (min-max scaling with window functions).
-- Alternative: keep Python and run it on Dataproc Serverless (submission_method).
with f as (
    select subscriber_id, days_since_last_use, tickets_90d, avg_daily_mb
    from {{ ref('fct_churn_features') }}
),

scaled as (
    select
        subscriber_id,
        safe_divide(days_since_last_use - min(days_since_last_use) over (),
                    max(days_since_last_use) over () - min(days_since_last_use) over ()) as a,
        safe_divide(tickets_90d - min(tickets_90d) over (),
                    max(tickets_90d) over () - min(tickets_90d) over ())                 as b,
        safe_divide(avg_daily_mb - min(avg_daily_mb) over (),
                    max(avg_daily_mb) over () - min(avg_daily_mb) over ())               as c
    from f
)

select
    subscriber_id,
    0.5 * ifnull(a, 0) + 0.3 * ifnull(b, 0) + 0.2 * (1 - ifnull(c, 0)) as churn_score
from scaled
