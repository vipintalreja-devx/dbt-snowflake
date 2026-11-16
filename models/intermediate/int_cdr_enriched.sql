{{
    config(
        materialized='incremental',
        unique_key='cdr_id',
        incremental_strategy='merge',
        cluster_by=['start_date', 'msisdn'],
        on_schema_change='append_new_columns',
        tags=['heavy']
    )
}}

with src as (
    select * from {{ ref('stg_cdr') }}
    {% if is_incremental() %}
    where loaded_at > (select coalesce(max(loaded_at), '1900-01-01'::timestamp_ntz) from {{ this }})
    {% endif %}
),

dedup as (
    select * from src
    qualify row_number() over (partition by cdr_id order by loaded_at desc) = 1
)

select
    d.*,
    d.start_ts::date                                         as start_date,
    {{ to_local_ts('d.start_ts') }}                          as start_ts_local,
    t.city                                                   as cell_city,
    t.region                                                 as cell_region,
    t.tech                                                   as cell_tech,
    iff(d.call_type = 'DATA', d.bytes_used / 1048576, null)  as mb_used,
    {{ hash_key(['d.cdr_id', 'd.msisdn']) }}                 as cdr_key
from dedup d
left join {{ ref('tower_cells') }} t on d.cell_id = t.cell_id
