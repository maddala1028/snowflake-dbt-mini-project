/*==============================================================================
  Script: 01_create_framework_schemas.sql
  Purpose: Create schemas required by the metadata-driven ingestion framework.
==============================================================================*/

use database DBT_MINI_PROJECT;

create schema if not exists CONTROL
    comment = 'Configuration and data-contract metadata for ingestion';

create schema if not exists AUDIT
    comment = 'Batch, file and reconciliation audit information';

create schema if not exists REJECT
    comment = 'Rejected source records and validation failures';

create schema if not exists PROCEDURES
    comment = 'Reusable ingestion and orchestration procedures';

show schemas in database DBT_MINI_PROJECT;