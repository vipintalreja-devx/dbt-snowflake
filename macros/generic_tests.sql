{% test positive_value(model, column_name) %}
    select * from {{ model }} where {{ column_name }} < 0
{% endtest %}

{% test fresh_within_hours(model, column_name, hours=24) %}
    select 1
    from (select max({{ column_name }}) as m from {{ model }})
    where datediff(hour, m, current_timestamp()) > {{ hours }}
{% endtest %}

{% test valid_msisdn(model, column_name) %}
    select * from {{ model }}
    where not regexp_like({{ column_name }}, '^\\+?[0-9]{10,15}$')
{% endtest %}
