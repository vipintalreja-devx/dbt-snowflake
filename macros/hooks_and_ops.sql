{# ---------- hooks ---------- #}
{# set_query_tag removed: replaced by query-comment job-label in dbt_project.yml #}
{# grant_select removed: replaced by +grants config in dbt_project.yml #}

{% macro log_run_results(results) %}
    {% if execute and target.name == 'prod' %}
        {% for r in results %}
            {% set q %}
                insert into `{{ target.project }}.audit.dbt_run_log`
                select '{{ invocation_id }}', '{{ r.node.unique_id }}', '{{ r.status }}',
                       {{ r.execution_time }}, current_datetime()
            {% endset %}
            {% do run_query(q) %}
        {% endfor %}
    {% endif %}
{% endmacro %}

{# ---------- dbt run-operation macros ---------- #}

{# BigQuery has no dataset clone: clone every table one by one (zero-copy until changed) #}
{% macro clone_prod_to_dev(src_dataset='analytics', dst_dataset=none) %}
    {% set d = dst_dataset or 'dev_' ~ env_var('DBT_USER', 'x') %}
    {% do run_query('create schema if not exists `' ~ target.project ~ '.' ~ d ~ '`') %}
    {% set q %}
        select table_name from `{{ target.project }}.{{ src_dataset }}.INFORMATION_SCHEMA.TABLES`
        where table_type = 'BASE TABLE'
    {% endset %}
    {% if execute %}
        {% for row in run_query(q).rows %}
            {% do run_query('create or replace table `' ~ target.project ~ '.' ~ d ~ '.' ~ row[0]
                ~ '` clone `' ~ target.project ~ '.' ~ src_dataset ~ '.' ~ row[0] ~ '`') %}
        {% endfor %}
    {% endif %}
    {% do log('Cloned ' ~ src_dataset ~ ' to ' ~ d, info=True) %}
{% endmacro %}

{# Snowflake streams -> BigQuery change history (read later with CHANGES()) #}
{% macro enable_change_history() %}
    {% for t in ['cdr', 'subscribers', 'payments'] %}
        {% do run_query(
            'alter table ' ~ source('raw', t) ~ ' set options (enable_change_history = true)'
        ) %}
    {% endfor %}
{% endmacro %}

{# COPY INTO @stage -> EXPORT DATA to GCS. path is a gs:// prefix #}
{% macro unload_to_stage(relation, bucket, path) %}
    {% set sql %}
        export data options (
            uri = 'gs://{{ bucket }}/{{ path }}/*.parquet',
            format = 'PARQUET',
            overwrite = true
        ) as
        select * from {{ relation }}
    {% endset %}
    {% do run_query(sql) %}
{% endmacro %}

{# resume_warehouse removed: BigQuery has no warehouse to resume #}

{% macro purge_old_dev_schemas(days=7) %}
    {% set q %}
        select schema_name
        from `{{ target.project }}`.`region-{{ target.location | lower }}`.INFORMATION_SCHEMA.SCHEMATA
        where schema_name like 'dbt\\_%'
          and last_modified_time < timestamp_sub(current_timestamp(), interval {{ days }} day)
    {% endset %}
    {% if execute %}
        {% for row in run_query(q).rows %}
            {% do run_query('drop schema if exists `' ~ target.project ~ '.' ~ row[0] ~ '` cascade') %}
        {% endfor %}
    {% endif %}
{% endmacro %}
