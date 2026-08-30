{{
  config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key='payment_id',
    on_schema_change='sync_all_columns'
  )
}}

select
    p.payment_id,
    p.application_id,
    a.customer_key,
    p.payment_date,
    p.payment_amount,
    p.payment_status,
    p.payment_method,
    p.updated_at
from {{ ref('stg_payments') }} p
left join {{ ref('fct_applications') }} a using (application_id)

{% if is_incremental() %}
where p.updated_at >= (select coalesce(max(updated_at), '1900-01-01') from {{ this }})
{% endif %}

