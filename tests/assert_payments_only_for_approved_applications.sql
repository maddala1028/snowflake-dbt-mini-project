-- A completed payment must belong to an approved application.
-- Any row returned by this query causes the test to fail.

select
    p.payment_id,
    p.application_id,
    a.application_status
from {{ ref('stg_payments') }} p
join {{ ref('stg_applications') }} a using (application_id)
where p.payment_status = 'COMPLETED'
  and a.application_status <> 'APPROVED'

