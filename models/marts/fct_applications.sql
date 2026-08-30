{{
  config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key='application_id',
    on_schema_change='sync_all_columns'
  )
}}

select
    a.application_id,
    c.customer_key,
    a.customer_id,
    a.application_date,
    a.product_type,
    a.requested_amount,
    a.application_status,
    a.decision_date,
    datediff('day', a.application_date, a.decision_date) as decision_days,
    a.updated_at
from {{ ref('stg_applications') }} a
left join {{ ref('dim_customers') }} c using (customer_id)

{% if is_incremental() %}
where a.updated_at >= (select coalesce(max(updated_at), '1900-01-01') from {{ this }})
{% endif %}

