-- ============================================================
-- File: raw_payments.sql
-- Purpose: Create the enterprise RAW payments table
-- ============================================================

USE ROLE DBT_ROLE;
USE WAREHOUSE DBT_WH;
USE DATABASE DBT_MINI_PROJECT;
USE SCHEMA RAW;

CREATE TABLE IF NOT EXISTS RAW_PAYMENTS
(
    INGESTION_RECORD_ID   VARCHAR DEFAULT UUID_STRING(),
    ENTITY_NAME           VARCHAR NOT NULL,
    RAW_RECORD            VARIANT NOT NULL,
    RECORD_HASH           VARCHAR,

    SOURCE_SYSTEM         VARCHAR NOT NULL,
    SOURCE_OBJECT         VARCHAR,
    FILE_TYPE             VARCHAR NOT NULL,

    FILE_NAME             VARCHAR NOT NULL,
    FILE_ROW_NUMBER       NUMBER,
    FILE_CONTENT_KEY      VARCHAR,
    FILE_LAST_MODIFIED    TIMESTAMP_NTZ,

    SCAN_START_TIME       TIMESTAMP_LTZ,
    LOAD_TIMESTAMP        TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(),

    BATCH_ID              VARCHAR NOT NULL,
    RUN_MODE              VARCHAR NOT NULL,
    CONTRACT_VERSION      VARCHAR,

    SOURCE_DATE           DATE,
    BACKFILL_FROM_DATE    DATE,
    BACKFILL_TO_DATE      DATE
)
COMMENT = 'Immutable RAW payment records with source-file lineage';