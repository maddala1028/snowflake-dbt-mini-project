/*==============================================================================
  Script: 03_create_ingestion_batch_audit.sql
  Purpose: Record the status and metrics of each ingestion batch.
==============================================================================*/

create table if not exists DBT_MINI_PROJECT.AUDIT.INGESTION_BATCH_AUDIT
(
    batch_id                 varchar(100)  not null,
    parent_batch_id          varchar(100),
    entity_name              varchar(100)  not null,

    contract_id              number,
    contract_version         varchar(30),

    run_mode                 varchar(30)   not null,
    force_reload             boolean       not null default false,
    backfill_request_id      varchar(100),
    backfill_from            timestamp_ntz,
    backfill_to              timestamp_ntz,

    batch_status             varchar(30)   not null,
    start_timestamp          timestamp_ntz not null default current_timestamp(),
    end_timestamp            timestamp_ntz,

    files_discovered         number        not null default 0,
    files_selected           number        not null default 0,
    files_loaded             number        not null default 0,
    files_skipped            number        not null default 0,
    files_failed             number        not null default 0,

    source_row_count         number        not null default 0,
    loaded_row_count         number        not null default 0,
    rejected_row_count       number        not null default 0,
    duplicate_row_count      number        not null default 0,

    reconciliation_status    varchar(30),

    snowflake_query_id       varchar(100),
    error_code               varchar(100),
    error_message            varchar(5000),

    initiated_by             varchar(100)  not null default current_user(),
    warehouse_name           varchar(100)  default current_warehouse(),
    role_name                varchar(100)  default current_role(),

    created_at               timestamp_ntz not null default current_timestamp(),
    updated_at               timestamp_ntz,

    constraint PK_INGESTION_BATCH_AUDIT primary key (batch_id)
)
comment = 'Execution status and aggregate metrics for ingestion batches';

