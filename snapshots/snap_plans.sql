{% snapshot snap_plans %}

{{
    config(
        target_schema='snapshots',
        unique_key='plan_id',
        strategy='check',
        check_cols=['plan_name', 'monthly_fee_cents', 'data_gb', 'voice_min']
    )
}}

select * from {{ source('raw', 'plans') }}

{% endsnapshot %}
