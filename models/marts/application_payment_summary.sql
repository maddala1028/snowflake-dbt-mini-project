{{ config(materialized='table') }}

with payment_totals as (
    select
        application_id,
        count_if(payment_status = 'COMPLETED') as completed_payment_count,
        sum(case when payment_status = 'COMPLETED' then payment_amount else 0 end) as total_paid_amount,
        max(case when payment_status = 'COMPLETED' then payment_date end) as latest_payment_date
    from {{ ref('fct_payments') }}
    group by application_id
)

select
    a.application_id,
    a.customer_id,
    c.customer_name,
    c.city,
    a.product_type,
    a.application_status,
    a.requested_amount,
    coalesce(p.completed_payment_count, 0) as completed_payment_count,
    coalesce(p.total_paid_amount, 0) as total_paid_amount,
    a.requested_amount - coalesce(p.total_paid_amount, 0) as remaining_amount,
    p.latest_payment_date
from {{ ref('fct_applications') }} a
left join {{ ref('dim_customers') }} c using (customer_key)
left join payment_totals p using (application_id)

