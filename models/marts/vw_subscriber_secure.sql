-- Snowflake secure view -> BigQuery authorized view.
-- Role checks (IS_ROLE_IN_SESSION) are replaced by IAM on this dataset/view.
{{
    config(
        materialized='view',
        grant_access_to=[{'project': target.database, 'dataset': 'telco_marts'}]
    )
}}

select subscriber_id, msisdn, city, state, plan_name, status
from {{ ref('dim_subscriber') }}
