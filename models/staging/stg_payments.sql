select
    trim(payment_id) as payment_id,
    trim(application_id) as application_id,
    to_date(payment_date) as payment_date,
    payment_amount::number(12,2) as payment_amount,
    {{ clean_text('payment_status') }} as payment_status,
    {{ clean_text('payment_method') }} as payment_method,
    to_timestamp_ntz(updated_at) as updated_at
from {{ ref('payments') }}

