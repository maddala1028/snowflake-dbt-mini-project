-- ============================================================
-- File: load_raw_customers.sql
-- Purpose: Manually load customer CSV data into RAW_CUSTOMERS
-- ============================================================

USE ROLE DBT_ROLE;
USE WAREHOUSE DBT_WH;
USE DATABASE DBT_MINI_PROJECT;

-- Load the source file
COPY INTO DBT_MINI_PROJECT.RAW.RAW_CUSTOMERS
(
    ENTITY_NAME,
    RAW_RECORD,
    SOURCE_SYSTEM,
    SOURCE_OBJECT,
    FILE_TYPE,
    FILE_NAME,
    FILE_ROW_NUMBER,
    FILE_CONTENT_KEY,
    FILE_LAST_MODIFIED,
    SCAN_START_TIME,
    LOAD_TIMESTAMP,
    BATCH_ID,
    RUN_MODE,
    CONTRACT_VERSION,
    SOURCE_DATE,
    BACKFILL_FROM_DATE,
    BACKFILL_TO_DATE
)
FROM
(
    SELECT
        'CUSTOMERS',

        OBJECT_CONSTRUCT(
            'customer_id',     t.$1::VARCHAR,
            'customer_name',   t.$2::VARCHAR,
            'email',           t.$3::VARCHAR,
            'city',            t.$4::VARCHAR,
            'customer_status', t.$5::VARCHAR,
            'created_at',      t.$6::VARCHAR,
            'updated_at',      t.$7::VARCHAR
        ),

        'AWS_S3',
        'CUSTOMERS',
        'CSV',

        METADATA$FILENAME,
        METADATA$FILE_ROW_NUMBER,
        METADATA$FILE_CONTENT_KEY,
        METADATA$FILE_LAST_MODIFIED,
        METADATA$START_SCAN_TIME,
        METADATA$START_SCAN_TIME,

        'HIST_20260830_001',
        'BACKFILL',
        '1.0',

        TO_DATE(METADATA$FILE_LAST_MODIFIED),
        NULL::DATE,
        NULL::DATE

    FROM @DBT_MINI_PROJECT.DBT_MINI_DEV.S3_DBT_MINI_STAGE/customers/
    (
        FILE_FORMAT =>
          DBT_MINI_PROJECT.DBT_MINI_DEV.CSV_FILE_FORMAT
    ) t
)
ON_ERROR = 'ABORT_STATEMENT';

-- Populate record-level hashes
UPDATE DBT_MINI_PROJECT.RAW.RAW_CUSTOMERS
SET RECORD_HASH = SHA2(TO_JSON(RAW_RECORD), 256)
WHERE BATCH_ID = 'HIST_20260830_001'
  AND RECORD_HASH IS NULL;

  select * from DBT_MINI_PROJECT.RAW.RAW_CUSTOMERS
  limit 100;