{# ---- small helpers using Snowflake functions ---- #}

{% macro cents_to_dollars(col, scale=2) %}
    ({{ col }}::number(18,0) / 100)::number(18, {{ scale }})
{% endmacro %}

{% macro safe_divide(n, d) %}
    div0null({{ n }}, {{ d }})
{% endmacro %}

{% macro mask_pii(col) %}
    sha2(lower(trim({{ col }})), 256)
{% endmacro %}

{% macro to_local_ts(col) %}
    convert_timezone('UTC', '{{ var("tz") }}', {{ col }}::timestamp_ntz)
{% endmacro %}

{% macro date_spine_sf(start_date, days) %}
    select dateadd(day, seq4(), '{{ start_date }}'::date) as date_day
    from table(generator(rowcount => {{ days }}))
{% endmacro %}

{# cross-adapter style macro: Snowflake implementation + default #}
{% macro hash_key(cols) %}
    {{ return(adapter.dispatch('hash_key', 'telco')(cols)) }}
{% endmacro %}

{% macro snowflake__hash_key(cols) %}
    md5_binary(concat_ws('|', {% for c in cols %}coalesce({{ c }}::varchar, '')
        {%- if not loop.last %}, {% endif %}{% endfor %}))
{% endmacro %}

{% macro default__hash_key(cols) %}
    md5(concat({% for c in cols %}coalesce(cast({{ c }} as string), ''){% if not loop.last %}, '|', {% endif %}{% endfor %}))
{% endmacro %}

{# jinja-generated pivot #}
{% macro pivot_sum(column, values, measure, prefix='') %}
    {% for v in values %}
        sum(iff({{ column }} = '{{ v }}', {{ measure }}, 0)) as {{ prefix }}{{ v | lower }}
        {%- if not loop.last %},{% endif %}
    {% endfor %}
{% endmacro %}
