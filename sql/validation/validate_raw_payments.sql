/*==============================================================================
  File Name   : validate_raw_payments.sql
  Purpose     : Validate payment records loaded into the RAW layer.
  Target Table: DBT_MINI_PROJECT.RAW.RAW_PAYMENTS

  Validation checks:
    1. Total number of records loaded
    2. Uniqueness of ingestion record IDs
    3. Uniqueness of source payment IDs
    4. Missing record hashes
    5. Missing source-file content keys
==============================================================================*/

USE ROLE DBT_ROLE;
USE WAREHOUSE DBT_WH;
USE DATABASE DBT_MINI_PROJECT;

/*
  Perform high-level RAW payment validation.

  Expected results:
    TOTAL_ROWS = UNIQUE_INGESTION_IDS
        Every RAW row must have a unique ingestion identifier.

    TOTAL_ROWS = UNIQUE_PAYMENTS
        Expected only when each payment_id appears once in the source.
        If multiple versions of a payment are allowed, this can be different.

    MISSING_HASHES = 0
        Every record must have a hash for duplicate/change detection.

    MISSING_CONTENT_KEYS = 0
        Every row must contain the Snowflake source-file content key.
*/

SELECT
    -- Total number of payment records loaded into the RAW table.
    COUNT(*) AS TOTAL_ROWS,

    -- Number of distinct technical ingestion identifiers.
    COUNT(DISTINCT INGESTION_RECORD_ID) AS UNIQUE_INGESTION_IDS,

    -- Number of distinct business payment identifiers inside RAW_RECORD.
    COUNT(DISTINCT RAW_RECORD:payment_id::VARCHAR) AS UNIQUE_PAYMENTS,

    -- Number of records where the record-level SHA-256 hash is missing.
    COUNT_IF(RECORD_HASH IS NULL) AS MISSING_HASHES,

    -- Number of records where the Snowflake file content key is missing.
    COUNT_IF(FILE_CONTENT_KEY IS NULL) AS MISSING_CONTENT_KEYS

FROM RAW.RAW_PAYMENTS;

--> Check statuses:
SELECT
    RAW_RECORD:payment_status::VARCHAR AS PAYMENT_STATUS,
    COUNT(*) AS ROW_COUNT
FROM RAW.RAW_PAYMENTS
GROUP BY RAW_RECORD:payment_status::VARCHAR
ORDER BY PAYMENT_STATUS;


--> Validate required fields:
SELECT COUNT(*) AS INVALID_REQUIRED_FIELDS
FROM RAW.RAW_PAYMENTS
WHERE RAW_RECORD:payment_id IS NULL
   OR RAW_RECORD:application_id IS NULL
   OR RAW_RECORD:payment_date IS NULL
   OR RAW_RECORD:payment_amount IS NULL
   OR RAW_RECORD:payment_status IS NULL
   OR RAW_RECORD:payment_method IS NULL
   OR RAW_RECORD:updated_at IS NULL;

--> Check for orphan payments

SELECT COUNT(*) AS ORPHAN_PAYMENTS
FROM RAW.RAW_PAYMENTS p
LEFT JOIN RAW.RAW_APPLICATIONS a
    ON p.RAW_RECORD:application_id::VARCHAR =
       a.RAW_RECORD:application_id::VARCHAR
WHERE a.RAW_RECORD:application_id IS NULL;


-->
SELECT COUNT(*) AS PAYMENTS_FOR_NON_APPROVED_APPLICATIONS
FROM RAW.RAW_PAYMENTS p
JOIN RAW.RAW_APPLICATIONS a
    ON p.RAW_RECORD:application_id::VARCHAR =
       a.RAW_RECORD:application_id::VARCHAR
WHERE a.RAW_RECORD:application_status::VARCHAR <> 'APPROVED';