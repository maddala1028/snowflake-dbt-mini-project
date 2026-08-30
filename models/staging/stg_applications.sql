select
    trim(application_id) as application_id,
    trim(customer_id) as customer_id,
    to_date(application_date) as application_date,
    {{ clean_text('product_type') }} as product_type,
    requested_amount::number(12,2) as requested_amount,
    {{ clean_text('application_status') }} as application_status,
    to_date(decision_date) as decision_date,
    to_timestamp_ntz(updated_at) as updated_at
from {{ ref('applications') }}

