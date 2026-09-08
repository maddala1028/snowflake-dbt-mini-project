{{ config(materialized = 'table', tags = ['gold', 'mart', 'customers']) }}

with application_metrics as (
    select
        customer_key,
        sum(application_count) as application_count,
        sum(approved_count) as approved_application_count,
        sum(rejected_count) as rejected_application_count,
        sum(requested_amount) as total_requested_amount,
        sum(approved_requested_amount) as approved_requested_amount,
        avg(decision_turnaround_days) as average_decision_days
    from {{ ref('fct_applications') }}
    group by customer_key
),

payment_metrics as (
    select
        customer_key,
        sum(payment_count) as payment_count,
        sum(completed_count) as completed_payment_count,
        sum(failed_count) as failed_payment_count,
        sum(refunded_count) as refunded_payment_count,
        sum(payment_amount) as total_payment_amount,
        sum(completed_payment_amount) as completed_payment_amount,
        sum(refunded_payment_amount) as refunded_payment_amount
    from {{ ref('fct_payments') }}
    group by customer_key
)

select
    customer.customer_key,
    customer.customer_id,
    customer.customer_name,
    customer.city,
    customer.customer_status,
    coalesce(application.application_count, 0) as application_count,
    coalesce(application.approved_application_count, 0) as approved_application_count,
    coalesce(application.rejected_application_count, 0) as rejected_application_count,
    coalesce(application.total_requested_amount, 0) as total_requested_amount,
    coalesce(application.approved_requested_amount, 0) as approved_requested_amount,
    application.average_decision_days,
    coalesce(payment.payment_count, 0) as payment_count,
    coalesce(payment.completed_payment_count, 0) as completed_payment_count,
    coalesce(payment.failed_payment_count, 0) as failed_payment_count,
    coalesce(payment.refunded_payment_count, 0) as refunded_payment_count,
    coalesce(payment.total_payment_amount, 0) as total_payment_amount,
    coalesce(payment.completed_payment_amount, 0) as completed_payment_amount,
    coalesce(payment.refunded_payment_amount, 0) as refunded_payment_amount,
    application.application_count is null as has_no_applications,
    application.application_count is not null
        and coalesce(payment.completed_payment_count, 0) = 0
        as has_no_completed_payment
from {{ ref('dim_customers') }} as customer
left join application_metrics as application using (customer_key)
left join payment_metrics as payment using (customer_key)
where not customer.is_unknown_customer
