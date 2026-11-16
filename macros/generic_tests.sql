{% test positive_value(model, column_name) %}
    select * from {{ model }} where {{ column_name }} < 0
{% endtest %}

{% test fresh_within_hours(model, column_name, hours=24) %}
    select 1
    from (select max(cast({{ column_name }} as timestamp)) as m from {{ model }})
    where timestamp_diff(current_timestamp(), m, hour) > {{ hours }}
{% endtest %}

{% test valid_msisdn(model, column_name) %}
    select * from {{ model }}
    where not regexp_contains({{ column_name }}, r'^\+?[0-9]{10,15}$')
{% endtest %}
