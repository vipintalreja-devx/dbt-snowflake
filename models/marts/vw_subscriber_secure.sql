{{ config(materialized='view', secure=true, copy_grants=true) }}

select subscriber_id, msisdn, city, state, plan_name, status
from {{ ref('dim_subscriber') }}
where is_role_in_session('ANALYST_ROLE')
   or current_role() = 'TRANSFORMER'
