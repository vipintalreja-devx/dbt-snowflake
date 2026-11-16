select cdr_id
from {{ ref('int_cdr_enriched') }}
where start_ts > dateadd(day, 1, current_timestamp())
