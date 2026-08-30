select
    trim(customer_id) as customer_id,
    trim(customer_name) as customer_name,
    lower(trim(email)) as email,
    initcap(trim(city)) as city,
    {{ clean_text('customer_status') }} as customer_status,
    to_timestamp_ntz(created_at) as created_at,
    to_timestamp_ntz(updated_at) as updated_at
from {{ ref('customers') }}

