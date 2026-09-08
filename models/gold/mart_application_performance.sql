{{ config(materialized = 'table', tags = ['gold', 'mart', 'applications']) }}

select
    application_date_key,
    application_date::date as application_date,
    sum(application_count) as application_count,
    sum(submitted_count) as submitted_count,
    sum(under_review_count) as under_review_count,
    sum(approved_count) as approved_count,
    sum(rejected_count) as rejected_count,
    sum(requested_amount) as total_requested_amount,
    sum(approved_requested_amount) as approved_requested_amount,
    avg(requested_amount) as average_requested_amount,
    avg(decision_turnaround_days) as average_decision_days,
    round(100 * sum(approved_count) / nullif(sum(application_count), 0), 2) as approval_rate_pct,
    round(100 * sum(rejected_count) / nullif(sum(application_count), 0), 2) as rejection_rate_pct,
    sum(iff(is_orphan_customer, 1, 0)) as orphan_application_count
from {{ ref('fct_applications') }}
group by application_date_key, application_date::date
