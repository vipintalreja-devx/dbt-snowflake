select cdr_id
from {{ ref('int_cdr_enriched') }}
where start_ts > datetime_add(current_datetime(), interval 1 day)
