{{ config(
    materialized = 'table',
    tags = ['gold', 'fact', 'payments']
) }}

with payments as (

    select
        payment.*,
        application.application_key as resolved_application_key,
        application.customer_key as resolved_customer_key,
        application.decision_date

    from {{ ref('silver_payments') }} as payment
    left join {{ ref('dim_applications') }} as application
        on payment.application_id = application.application_id
       and not application.is_unknown_application

)

select
    {{ dbt_utils.generate_surrogate_key(['payment_id']) }} as payment_key,
    coalesce(
        resolved_application_key,
        {{ dbt_utils.generate_surrogate_key(["'__UNKNOWN__'"]) }}
    ) as application_key,
    coalesce(
        resolved_customer_key,
        {{ dbt_utils.generate_surrogate_key(["'__UNKNOWN__'"]) }}
    ) as customer_key,
    to_number(to_char(payment_date, 'YYYYMMDD')) as payment_date_key,

    payment_id,
    application_id,
    payment_status,
    payment_date,
    payment_method,

    1 as payment_count,
    payment_amount,
    iff(payment_status = 'PENDING', 1, 0) as pending_count,
    iff(payment_status = 'COMPLETED', 1, 0) as completed_count,
    iff(payment_status = 'FAILED', 1, 0) as failed_count,
    iff(payment_status = 'REFUNDED', 1, 0) as refunded_count,
    iff(payment_status = 'COMPLETED', payment_amount, 0) as completed_payment_amount,
    iff(payment_status = 'REFUNDED', payment_amount, 0) as refunded_payment_amount,
    case
        when decision_date is not null
            then datediff(day, decision_date, payment_date)
    end as days_from_decision_to_payment,

    resolved_application_key is null as is_orphan_application,
    source_system,
    source_date,
    load_timestamp as silver_load_timestamp

from payments
