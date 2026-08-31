/*==============================================================================
  Script: recover_stale_development_batch.sql
  Purpose: Close a stale development batch left in DISCOVERING status.

  Important:
  - This is a one-time recovery script.
  - Do not include it in routine deployment or orchestration.
==============================================================================*/

update DBT_MINI_PROJECT.AUDIT.INGESTION_BATCH_AUDIT
set
    batch_status = 'FAILED',
    end_timestamp = current_timestamp(),
    error_code = 'DEV_RECOVERY',
    error_message =
        'Initial development attempt failed before exception handling was corrected',
    updated_at = current_timestamp()
where entity_name = 'CUSTOMERS'
  and batch_status = 'DISCOVERING'
  and start_timestamp < dateadd(minute, -5, current_timestamp());

