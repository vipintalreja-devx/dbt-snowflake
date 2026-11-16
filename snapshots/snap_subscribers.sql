{% snapshot snap_subscribers %}

{{
    config(
        target_schema='snapshots',
        unique_key='subscriber_id',
        strategy='timestamp',
        updated_at='updated_at',
        invalidate_hard_deletes=True
    )
}}

select * from {{ source('raw', 'subscribers') }}

{% endsnapshot %}
