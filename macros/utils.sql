{# ---- small helpers, BigQuery versions ---- #}

{% macro cents_to_dollars(col, scale=2) %}
    round(cast({{ col }} as numeric) / 100, {{ scale }})
{% endmacro %}

{% macro safe_divide(n, d) %}
    safe_divide({{ n }}, {{ d }})
{% endmacro %}

{# returns hex text, like Snowflake SHA2 #}
{% macro mask_pii(col) %}
    to_hex(sha256(lower(trim({{ col }}))))
{% endmacro %}

{# col must be DATETIME (UTC) -> local DATETIME #}
{% macro to_local_ts(col) %}
    datetime(timestamp({{ col }}, 'UTC'), '{{ var("tz") }}')
{% endmacro %}

{% macro date_spine_sf(start_date, days) %}
    select date_day
    from unnest(generate_date_array(
        date '{{ start_date }}',
        date_add(date '{{ start_date }}', interval {{ days - 1 }} day)
    )) as date_day
{% endmacro %}

{% macro hash_key(cols) %}
    {{ return(adapter.dispatch('hash_key', 'telco')(cols)) }}
{% endmacro %}

{# BigQuery has no CONCAT_WS: build an array and join it. Returns hex text. #}
{% macro bigquery__hash_key(cols) %}
    to_hex(md5(array_to_string([
        {% for c in cols %}ifnull(cast({{ c }} as string), ''){% if not loop.last %}, {% endif %}{% endfor %}
    ], '|')))
{% endmacro %}

{% macro default__hash_key(cols) %}
    md5(concat({% for c in cols %}coalesce(cast({{ c }} as string), ''){% if not loop.last %}, '|', {% endif %}{% endfor %}))
{% endmacro %}

{% macro pivot_sum(column, values, measure, prefix='') %}
    {% for v in values %}
        sum(if({{ column }} = '{{ v }}', {{ measure }}, 0)) as {{ prefix }}{{ v | lower }}
        {%- if not loop.last %},{% endif %}
    {% endfor %}
{% endmacro %}
