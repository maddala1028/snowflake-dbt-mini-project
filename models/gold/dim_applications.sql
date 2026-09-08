{{ config(
    materialized = 'table',
    tags = ['gold', 'dimension', 'applications']
) }}

with applications as (

    select
        {{ dbt_utils.generate_surrogate_key(['application.application_id']) }} as application_key,
        coalesce(
            customer.customer_key,
            {{ dbt_utils.generate_surrogate_key(["'__UNKNOWN__'"]) }}
        ) as customer_key,
        application.application_id,
        application.customer_id,
        application.application_status,
        application.application_date,
        application.requested_amount,
        application.decision_date,
        application.source_system,
        application.source_date,
        application.load_timestamp as silver_load_timestamp,
        customer.customer_key is null as is_orphan_customer,
        false as is_unknown_application

    from {{ ref('silver_applications') }} as application
    left join {{ ref('dim_customers') }} as customer
        on application.customer_id = customer.customer_id
       and not customer.is_unknown_customer

),

unknown_application as (

    select
        {{ dbt_utils.generate_surrogate_key(["'__UNKNOWN__'"]) }} as application_key,
        {{ dbt_utils.generate_surrogate_key(["'__UNKNOWN__'"]) }} as customer_key,
        '__UNKNOWN__'::varchar as application_id,
        '__UNKNOWN__'::varchar as customer_id,
        'UNKNOWN'::varchar as application_status,
        cast(null as timestamp_ntz) as application_date,
        cast(0 as number(18, 2)) as requested_amount,
        cast(null as timestamp_ntz) as decision_date,
        'SYSTEM'::varchar as source_system,
        cast(null as date) as source_date,
        cast(null as timestamp_ntz) as silver_load_timestamp,
        false as is_orphan_customer,
        true as is_unknown_application

)

select * from applications
union all
select * from unknown_application
