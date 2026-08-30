/*
  File: validate_raw_customers.sql
  Purpose: Post-load validation for the manual CUSTOMERS RAW load.
  Expected batch: HIST_20260830_001
  Expected rows: 1000
*/

USE DATABASE DBT_MINI_PROJECT;
USE SCHEMA RAW;

-- 1. Batch-level validation summary. PASS is expected for every check.
WITH batch_data AS (
    SELECT *
    FROM RAW_CUSTOMERS
    WHERE BATCH_ID = 'HIST_20260830_001'
), checks AS (
    SELECT 'ROW_COUNT' AS CHECK_NAME, 1000 AS EXPECTED_VALUE,
           COUNT(*) AS ACTUAL_VALUE
    FROM batch_data

    UNION ALL

    SELECT 'DUPLICATE_INGESTION_RECORD_ID', 0,
           COUNT(*)
    FROM (
        SELECT INGESTION_RECORD_ID
        FROM batch_data
        GROUP BY INGESTION_RECORD_ID
        HAVING COUNT(*) > 1
    )

    UNION ALL

    SELECT 'NULL_MANDATORY_AUDIT_COLUMNS', 0,
           COUNT_IF(
               INGESTION_RECORD_ID IS NULL OR ENTITY_NAME IS NULL
               OR RAW_RECORD IS NULL OR SOURCE_SYSTEM IS NULL
               OR FILE_TYPE IS NULL OR FILE_NAME IS NULL
               OR LOAD_TIMESTAMP IS NULL OR BATCH_ID IS NULL
               OR RUN_MODE IS NULL
           )
    FROM batch_data

    UNION ALL

    SELECT 'NULL_RECORD_HASH', 0, COUNT_IF(RECORD_HASH IS NULL)
    FROM batch_data

    UNION ALL

    SELECT 'DUPLICATE_RECORD_HASH', 0, COUNT(*)
    FROM (
        SELECT RECORD_HASH
        FROM batch_data
        WHERE RECORD_HASH IS NOT NULL
        GROUP BY RECORD_HASH
        HAVING COUNT(*) > 1
    )

    UNION ALL

    SELECT 'MISSING_BUSINESS_FIELDS', 0,
           COUNT_IF(
               NULLIF(TRIM(RAW_RECORD:customer_id::VARCHAR), '') IS NULL
               OR NULLIF(TRIM(RAW_RECORD:customer_name::VARCHAR), '') IS NULL
               OR NULLIF(TRIM(RAW_RECORD:email::VARCHAR), '') IS NULL
           )
    FROM batch_data

    UNION ALL

    SELECT 'DUPLICATE_CUSTOMER_ID', 0, COUNT(*)
    FROM (
        SELECT RAW_RECORD:customer_id::VARCHAR AS CUSTOMER_ID
        FROM batch_data
        GROUP BY CUSTOMER_ID
        HAVING COUNT(*) > 1
    )

    UNION ALL

    SELECT 'INVALID_CUSTOMER_STATUS', 0,
           COUNT_IF(
               UPPER(RAW_RECORD:customer_status::VARCHAR)
               NOT IN ('ACTIVE', 'INACTIVE', 'SUSPENDED')
               OR RAW_RECORD:customer_status IS NULL
           )
    FROM batch_data

    UNION ALL

    SELECT 'INVALID_TIMESTAMP_VALUES', 0,
           COUNT_IF(
               TRY_TO_TIMESTAMP_NTZ(RAW_RECORD:created_at::VARCHAR) IS NULL
               OR TRY_TO_TIMESTAMP_NTZ(RAW_RECORD:updated_at::VARCHAR) IS NULL
           )
    FROM batch_data
)
SELECT
    CHECK_NAME,
    EXPECTED_VALUE,
    ACTUAL_VALUE,
    ACTUAL_VALUE - EXPECTED_VALUE AS VARIANCE,
    IFF(ACTUAL_VALUE = EXPECTED_VALUE, 'PASS', 'FAIL') AS CHECK_STATUS
FROM checks
ORDER BY CHECK_NAME;

-- 2. Customer status distribution for profiling/reconciliation.
SELECT
    RAW_RECORD:customer_status::VARCHAR AS CUSTOMER_STATUS,
    COUNT(*) AS RECORD_COUNT
FROM RAW_CUSTOMERS
WHERE BATCH_ID = 'HIST_20260830_001'
GROUP BY CUSTOMER_STATUS
ORDER BY CUSTOMER_STATUS;

-- 3. Display failed business records, if any.
SELECT
    INGESTION_RECORD_ID,
    FILE_NAME,
    FILE_ROW_NUMBER,
    RAW_RECORD
FROM RAW_CUSTOMERS
WHERE BATCH_ID = 'HIST_20260830_001'
  AND (
      NULLIF(TRIM(RAW_RECORD:customer_id::VARCHAR), '') IS NULL
      OR NULLIF(TRIM(RAW_RECORD:customer_name::VARCHAR), '') IS NULL
      OR NULLIF(TRIM(RAW_RECORD:email::VARCHAR), '') IS NULL
      OR UPPER(RAW_RECORD:customer_status::VARCHAR)
         NOT IN ('ACTIVE', 'INACTIVE', 'SUSPENDED')
      OR TRY_TO_TIMESTAMP_NTZ(RAW_RECORD:created_at::VARCHAR) IS NULL
      OR TRY_TO_TIMESTAMP_NTZ(RAW_RECORD:updated_at::VARCHAR) IS NULL
  )
ORDER BY FILE_ROW_NUMBER;

-- 4. Sample records for visual inspection.
SELECT *
FROM RAW_CUSTOMERS
WHERE BATCH_ID = 'HIST_20260830_001'
ORDER BY FILE_ROW_NUMBER
LIMIT 10;
