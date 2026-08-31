/*==============================================================================
  Script: 06_create_ingestion_reject.sql
  Purpose: Store records rejected during ingestion and contract validation.
==============================================================================*/

create table if not exists DBT_MINI_PROJECT.REJECT.INGESTION_REJECT
(
    reject_id                number autoincrement start 1 increment 1,
    batch_id                 varchar(100)  not null,
    file_load_id             number,
    entity_name              varchar(100)  not null,

    contract_id              number,
    contract_version         varchar(30),

    full_file_path           varchar(1500),
    file_name                varchar(1000),
    file_row_number          number,

    ingestion_record_id      varchar(100),
    record_hash              varchar(500),
    raw_record               variant,

    rejection_category       varchar(100)  not null,
    rejection_code           varchar(100)  not null,
    rejection_reason         varchar(5000) not null,
    failed_fields            array,
    validation_details       variant,

    resolution_status        varchar(30)   not null default 'OPEN',
    resolution_notes         varchar(5000),
    resolved_at              timestamp_ntz,
    resolved_by              varchar(100),

    reprocessed_batch_id     varchar(100),
    reprocessed_at           timestamp_ntz,

    rejected_at              timestamp_ntz not null default current_timestamp(),
    created_by               varchar(100)  not null default current_user(),

    constraint PK_INGESTION_REJECT primary key (reject_id)
)
comment = 'Records rejected by parsing, contract and ingestion validations';

select
    table_catalog,
    table_schema,
    table_name,
    row_count
from DBT_MINI_PROJECT.information_schema.tables
where table_schema = 'REJECT'
  and table_name = 'INGESTION_REJECT';