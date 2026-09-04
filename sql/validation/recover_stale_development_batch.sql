/*==============================================================================
  Script: recover_stale_development_batch.sql
  Purpose: Close ONE confirmed abandoned Customers development batch.

  Important:
  - This is a one-time recovery script.
  - Do not include it in routine deployment or orchestration.
  - Confirm the development environment and that no query/task/orchestrator
    is still processing the batch. Age alone does not prove abandonment.
  - Replace REPLACE_WITH_CONFIRMED_BATCH_ID in all three queries with the same
    exact batch ID. Keep the separate placeholder-exclusion predicates intact.
  - Run preview first and require exactly ONE row; retain before/after evidence.
  - The UPDATE is commented out deliberately. Enable and run it separately only
    after confirming abandonment. Expect exactly ONE row updated; investigate
    zero rows rather than broadening the filter. State can change after preview.
  - This only changes audit state; it does not cancel work, roll back RAW data,
    or establish that retrying is safe. Do not run the entire file for recovery.
  - Restore the placeholder and disabled UPDATE before committing after use.
==============================================================================*/

-- 1. Read-only preview. The unchanged placeholder cannot match a row.
select batch_id, entity_name, batch_status, start_timestamp, end_timestamp,
       source_row_count, loaded_row_count, rejected_row_count,
       duplicate_row_count, error_code, error_message
from DBT_MINI_PROJECT.AUDIT.INGESTION_BATCH_AUDIT
where batch_id = 'REPLACE_WITH_CONFIRMED_BATCH_ID'
  and batch_id <> ('REPLACE_' || 'WITH_CONFIRMED_BATCH_ID')
  and entity_name = 'CUSTOMERS'
  and batch_status = 'DISCOVERING';

-- 2. Manual update: disabled by default. Review preview before enabling.
/*
update DBT_MINI_PROJECT.AUDIT.INGESTION_BATCH_AUDIT
set
    batch_status = 'FAILED',
    end_timestamp = current_timestamp(),
    error_code = 'DEV_RECOVERY',
    error_message =
        'Manual development recovery: batch confirmed abandoned by operator',
    updated_at = current_timestamp()
where batch_id = 'REPLACE_WITH_CONFIRMED_BATCH_ID'
  and batch_id <> ('REPLACE_' || 'WITH_CONFIRMED_BATCH_ID')
  and entity_name = 'CUSTOMERS'
  and batch_status = 'DISCOVERING';
*/

-- 3. Read-only verification: expect FAILED, DEV_RECOVERY and an end timestamp.
select batch_id, entity_name, batch_status, end_timestamp,
       error_code, error_message, updated_at
from DBT_MINI_PROJECT.AUDIT.INGESTION_BATCH_AUDIT
where batch_id = 'REPLACE_WITH_CONFIRMED_BATCH_ID'
  and batch_id <> ('REPLACE_' || 'WITH_CONFIRMED_BATCH_ID')
  and entity_name = 'CUSTOMERS';

