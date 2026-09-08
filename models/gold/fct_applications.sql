{{ config(
    materialized = 'table',
    tags = ['gold', 'fact', 'applications']
) }}

select
    application.application_key,
    application.customer_key,
    to_number(to_char(application.application_date, 'YYYYMMDD')) as application_date_key,
    case
        when application.decision_date is not null
            then to_number(to_char(application.decision_date, 'YYYYMMDD'))
    end as decision_date_key,

    application.application_id,
    application.customer_id,
    application.application_status,
    application.application_date,
    application.decision_date,

    1 as application_count,
    application.requested_amount,
    iff(application.application_status = 'SUBMITTED', 1, 0) as submitted_count,
    iff(application.application_status = 'UNDER_REVIEW', 1, 0) as under_review_count,
    iff(application.application_status = 'APPROVED', 1, 0) as approved_count,
    iff(application.application_status = 'REJECTED', 1, 0) as rejected_count,
    iff(
        application.application_status = 'APPROVED',
        application.requested_amount,
        0
    ) as approved_requested_amount,
    case
        when application.decision_date is not null
            then datediff(
                day,
                application.application_date,
                application.decision_date
            )
    end as decision_turnaround_days,

    application.is_orphan_customer,
    application.source_system,
    application.source_date,
    application.silver_load_timestamp

from {{ ref('dim_applications') }} as application
where not application.is_unknown_application
