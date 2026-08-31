/*==============================================================================
  Script: 04_create_file_load_audit.sql
  Purpose: Track each discovered file and support idempotent ingestion.
==============================================================================*/

create table if not exists DBT_MINI_PROJECT.AUDIT.FILE_LOAD_AUDIT
(
    file_load_id             number autoincrement start 1 increment 1,
    batch_id                 varchar(100)  not null,
    entity_name              varchar(100)  not null,

    contract_id              number,
    contract_version         varchar(30),

    stage_name               varchar(300)  not null,
    stage_path               varchar(500),
    file_name                varchar(1000) not null,
    full_file_path           varchar(1500) not null,

    file_type                varchar(20)   not null,
    file_size_bytes          number,
    file_last_modified       timestamp_tz,
    file_etag                varchar(500),

    file_content_key         varchar(500),
    file_checksum            varchar(500),

    load_attempt_number      number        not null default 1,
    file_status              varchar(30)   not null,
    skip_reason              varchar(1000),

    discovered_at            timestamp_ntz not null default current_timestamp(),
    load_start_timestamp     timestamp_ntz,
    load_end_timestamp       timestamp_ntz,

    source_row_count         number        not null default 0,
    loaded_row_count         number        not null default 0,
    rejected_row_count       number        not null default 0,
    duplicate_row_count      number        not null default 0,

    copy_query_id            varchar(100),
    error_code               varchar(100),
    error_message            varchar(5000),

    created_at               timestamp_ntz not null default current_timestamp(),
    created_by               varchar(100)  not null default current_user(),
    updated_at               timestamp_ntz,

    constraint PK_FILE_LOAD_AUDIT primary key (file_load_id)
)
comment = 'File discovery, idempotency, duplicate detection and load audit';

