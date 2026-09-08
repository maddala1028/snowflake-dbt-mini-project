{{ config(
    materialized = 'table',
    tags = ['gold', 'dimension', 'customers']
) }}

with customers as (

    select
        {{ dbt_utils.generate_surrogate_key(['customer_id']) }} as customer_key,
        customer_id,
        customer_name,
        email,
        city,
        customer_status,
        created_at,
        updated_at,
        source_system,
        source_date,
        load_timestamp as silver_load_timestamp,
        false as is_unknown_customer

    from {{ ref('silver_customers') }}

),

unknown_customer as (

    select
        {{ dbt_utils.generate_surrogate_key(["'__UNKNOWN__'"]) }} as customer_key,
        '__UNKNOWN__'::varchar as customer_id,
        'Unknown Customer'::varchar as customer_name,
        cast(null as varchar) as email,
        'Unknown'::varchar as city,
        'UNKNOWN'::varchar as customer_status,
        cast(null as timestamp_ntz) as created_at,
        cast(null as timestamp_ntz) as updated_at,
        'SYSTEM'::varchar as source_system,
        cast(null as date) as source_date,
        cast(null as timestamp_ntz) as silver_load_timestamp,
        true as is_unknown_customer

)

select * from customers
union all
select * from unknown_customer
