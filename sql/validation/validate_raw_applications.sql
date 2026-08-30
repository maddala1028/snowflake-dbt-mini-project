/*
  File: validate_raw_applications.sql
  Purpose: Post-load validation for the manual APPLICATIONS RAW load.
  Expected batch: HIST_20260830_002
  Expected rows: 1650
*/

USE DATABASE DBT_MINI_PROJECT;
USE SCHEMA RAW;

-- 1. Batch-level validation summary. PASS is expected for every check.
WITH batch_data AS (
    SELECT *
    FROM RAW_APPLICATIONS
    WHERE BATCH_ID = 'HIST_20260830_002'
), checks AS (
    SELECT 'ROW_COUNT' AS CHECK_NAME, 1650 AS EXPECTED_VALUE,
           COUNT(*) AS ACTUAL_VALUE
    FROM batch_data

    UNION ALL

    SELECT 'DUPLICATE_INGESTION_RECORD_ID', 0, COUNT(*)
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
               NULLIF(TRIM(RAW_RECORD:application_id::VARCHAR), '') IS NULL
               OR NULLIF(TRIM(RAW_RECORD:customer_id::VARCHAR), '') IS NULL
               OR NULLIF(TRIM(RAW_RECORD:application_status::VARCHAR), '') IS NULL
               OR TRY_TO_DATE(RAW_RECORD:application_date::VARCHAR) IS NULL
               OR TRY_TO_DECIMAL(RAW_RECORD:requested_amount::VARCHAR, 18, 2) IS NULL
           )
    FROM batch_data

    UNION ALL

    SELECT 'DUPLICATE_APPLICATION_ID', 0, COUNT(*)
    FROM (
        SELECT RAW_RECORD:application_id::VARCHAR AS APPLICATION_ID
        FROM batch_data
        GROUP BY APPLICATION_ID
        HAVING COUNT(*) > 1
    )

    UNION ALL

    SELECT 'INVALID_APPLICATION_STATUS', 0,
           COUNT_IF(
               UPPER(RAW_RECORD:application_status::VARCHAR)
               NOT IN ('SUBMITTED', 'UNDER_REVIEW', 'APPROVED', 'REJECTED')
               OR RAW_RECORD:application_status IS NULL
           )
    FROM batch_data

    UNION ALL

    SELECT 'INVALID_DECISION_DATE', 0,
           COUNT_IF(
               UPPER(RAW_RECORD:application_status::VARCHAR)
                   IN ('APPROVED', 'REJECTED')
               AND TRY_TO_DATE(RAW_RECORD:decision_date::VARCHAR) IS NULL
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

-- 2. Expected status distribution:
-- APPROVED=792, REJECTED=303, SUBMITTED=246, UNDER_REVIEW=309.
SELECT
    RAW_RECORD:application_status::VARCHAR AS APPLICATION_STATUS,
    COUNT(*) AS RECORD_COUNT
FROM RAW_APPLICATIONS
WHERE BATCH_ID = 'HIST_20260830_002'
GROUP BY APPLICATION_STATUS
ORDER BY APPLICATION_STATUS;

-- 3. Referential integrity: expected result is zero orphan applications.
SELECT COUNT(*) AS ORPHAN_APPLICATION_COUNT
FROM RAW_APPLICATIONS a
LEFT JOIN RAW_CUSTOMERS c
  ON a.RAW_RECORD:customer_id::VARCHAR = c.RAW_RECORD:customer_id::VARCHAR
 AND c.BATCH_ID = 'HIST_20260830_001'
WHERE a.BATCH_ID = 'HIST_20260830_002'
  AND c.INGESTION_RECORD_ID IS NULL;

-- 4. Display orphan applications, if any.
SELECT
    a.INGESTION_RECORD_ID,
    a.FILE_NAME,
    a.FILE_ROW_NUMBER,
    a.RAW_RECORD:application_id::VARCHAR AS APPLICATION_ID,
    a.RAW_RECORD:customer_id::VARCHAR AS CUSTOMER_ID,
    a.RAW_RECORD
FROM RAW_APPLICATIONS a
LEFT JOIN RAW_CUSTOMERS c
  ON a.RAW_RECORD:customer_id::VARCHAR = c.RAW_RECORD:customer_id::VARCHAR
 AND c.BATCH_ID = 'HIST_20260830_001'
WHERE a.BATCH_ID = 'HIST_20260830_002'
  AND c.INGESTION_RECORD_ID IS NULL
ORDER BY a.FILE_ROW_NUMBER;

-- 5. Display invalid application records, if any.
SELECT
    INGESTION_RECORD_ID,
    FILE_NAME,
    FILE_ROW_NUMBER,
    RAW_RECORD
FROM RAW_APPLICATIONS
WHERE BATCH_ID = 'HIST_20260830_002'
  AND (
      NULLIF(TRIM(RAW_RECORD:application_id::VARCHAR), '') IS NULL
      OR NULLIF(TRIM(RAW_RECORD:customer_id::VARCHAR), '') IS NULL
      OR UPPER(RAW_RECORD:application_status::VARCHAR)
         NOT IN ('SUBMITTED', 'UNDER_REVIEW', 'APPROVED', 'REJECTED')
      OR TRY_TO_DATE(RAW_RECORD:application_date::VARCHAR) IS NULL
      OR TRY_TO_DECIMAL(RAW_RECORD:requested_amount::VARCHAR, 18, 2) IS NULL
      OR (
          UPPER(RAW_RECORD:application_status::VARCHAR)
              IN ('APPROVED', 'REJECTED')
          AND TRY_TO_DATE(RAW_RECORD:decision_date::VARCHAR) IS NULL
      )
  )
ORDER BY FILE_ROW_NUMBER;

-- 6. Sample records for visual inspection.
SELECT *
FROM RAW_APPLICATIONS
WHERE BATCH_ID = 'HIST_20260830_002'
ORDER BY FILE_ROW_NUMBER
LIMIT 10;
