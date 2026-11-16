{# ---------- hooks ---------- #}

{% macro set_query_tag() %}
    {% if target.type == 'snowflake' %}
        alter session set query_tag = '{"app":"dbt","invocation":"{{ invocation_id }}","target":"{{ target.name }}"}'
    {% endif %}
{% endmacro %}

{% macro grant_select(role) %}
    {% if target.name == 'prod' %}
        grant select on {{ this }} to role {{ role }}
    {% endif %}
{% endmacro %}

{% macro log_run_results(results) %}
    {% if execute and target.name == 'prod' %}
        {% for r in results %}
            {% set q %}
                insert into {{ target.database }}.audit.dbt_run_log
                select '{{ invocation_id }}', '{{ r.node.unique_id }}', '{{ r.status }}',
                       {{ r.execution_time }}, current_timestamp()
            {% endset %}
            {% do run_query(q) %}
        {% endfor %}
    {% endif %}
{% endmacro %}

{# ---------- dbt run-operation macros ---------- #}

{% macro clone_prod_to_dev(src='TELCO_PROD', dst=none) %}
    {% set d = dst or 'TELCO_DEV_' ~ env_var('DBT_USER', 'X') %}
    {% do run_query('create or replace database ' ~ d ~ ' clone ' ~ src) %}
    {% do log('Cloned ' ~ src ~ ' to ' ~ d, info=True) %}
{% endmacro %}

{% macro create_streams() %}
    {% for t in ['cdr', 'subscribers', 'payments'] %}
        {% do run_query(
            'create stream if not exists ' ~ target.database ~ '.raw.strm_' ~ t
            ~ ' on table ' ~ source('raw', t)
            ~ ' append_only = ' ~ ('true' if t == 'cdr' else 'false')
        ) %}
    {% endfor %}
{% endmacro %}

{% macro unload_to_stage(relation, stage, path) %}
    {% set sql %}
        copy into @{{ stage }}/{{ path }}/
        from {{ relation }}
        file_format = (type = parquet)
        header = true
        overwrite = true
    {% endset %}
    {% do run_query(sql) %}
{% endmacro %}

{% macro resume_warehouse(wh) %}
    {% do run_query('alter warehouse ' ~ wh ~ ' resume if suspended') %}
{% endmacro %}

{% macro purge_old_dev_schemas(days=7) %}
    {% set q %}
        select schema_name from {{ target.database }}.information_schema.schemata
        where schema_name ilike 'DBT\\_%' escape '\\'
          and last_altered < dateadd(day, -{{ days }}, current_timestamp())
    {% endset %}
    {% if execute %}
        {% for row in run_query(q).rows %}
            {% do run_query('drop schema if exists ' ~ target.database ~ '.' ~ row[0] ~ ' cascade') %}
        {% endfor %}
    {% endif %}
{% endmacro %}
