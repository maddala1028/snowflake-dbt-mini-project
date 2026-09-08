{{ config(materialized = 'table', tags = ['gold', 'mart', 'payments']) }}

with daily_payment_metrics as (

select
    payment_date_key,
    payment_date::date as payment_date,
    coalesce(payment_method, 'UNKNOWN') as payment_method,
    sum(payment_count) as payment_count,
    sum(pending_count) as pending_count,
    sum(completed_count) as completed_count,
    sum(failed_count) as failed_count,
    sum(refunded_count) as refunded_count,
    sum(payment_amount) as total_payment_amount,
    sum(completed_payment_amount) as completed_payment_amount,
    sum(refunded_payment_amount) as refunded_payment_amount,
    avg(payment_amount) as average_payment_amount,
    avg(days_from_decision_to_payment) as average_days_from_decision_to_payment,
    round(100 * sum(completed_count) / nullif(sum(payment_count), 0), 2) as payment_success_rate_pct,
    round(100 * sum(failed_count) / nullif(sum(payment_count), 0), 2) as payment_failure_rate_pct,
    sum(iff(is_orphan_application, 1, 0)) as orphan_payment_count
from {{ ref('fct_payments') }}
group by payment_date_key, payment_date::date, coalesce(payment_method, 'UNKNOWN')

)

select
    {{ dbt_utils.generate_surrogate_key([
        'payment_date_key',
        'payment_method'
    ]) }} as payment_summary_key,
    *
from daily_payment_metrics
