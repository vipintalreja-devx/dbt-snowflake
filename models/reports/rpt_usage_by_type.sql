select
    date_trunc(start_date, month) as month,
    {{ pivot_sum('call_type', ['VOICE', 'SMS', 'DATA'], 'if(call_type = "DATA", bytes_used, duration_sec)', prefix='total_') }}
from {{ ref('int_cdr_enriched') }}
group by 1
