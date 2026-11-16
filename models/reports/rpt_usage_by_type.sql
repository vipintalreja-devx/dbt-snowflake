select
    date_trunc('month', start_date) as month,
    {{ pivot_sum('call_type', ['VOICE', 'SMS', 'DATA'], 'iff(call_type = \'DATA\', bytes_used, duration_sec)', prefix='total_') }}
from {{ ref('int_cdr_enriched') }}
group by 1
