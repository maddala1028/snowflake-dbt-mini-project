{{ config(materialized='table') }}

select
    {{ dbt_utils.generate_surrogate_key(['customer_id']) }} as customer_key,
    customer_id,
    customer_name,
    email,
    city,
    customer_status,
    created_at,
    updated_at
from {{ ref('stg_customers') }}

