{% macro clean_text(column_name) %}
    nullif(upper(trim({{ column_name }})), '')
{% endmacro %}

