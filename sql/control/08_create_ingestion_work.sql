/*==============================================================================
  Script: 08_create_ingestion_work.sql
  Purpose: Hold parsed records temporarily before RAW/reject routing.
==============================================================================*/

create transient table if not exists
    DBT_MINI_PROJECT.CONTROL.INGESTION_WORK
(
    work_record_id           number autoincrement start 1 increment 1,

    batch_id                 varchar(100)  not null,
    file_load_id             number,
    entity_name              varchar(100)  not null,

    contract_id              number,
    contract_version         varchar(30),

    ingestion_record_id      varchar(100)  not null,
    raw_record               variant,
    record_hash              varchar(500),

    source_system            varchar(100),
    source_object            varchar(1500),
    file_type                varchar(20),
    file_name                varchar(1000),
    file_row_number          number,
    file_content_key         varchar(500),
    file_last_modified       timestamp_ntz,
    scan_start_time          timestamp_ltz,
    load_timestamp           timestamp_ltz,

    run_mode                 varchar(30),
    source_date              date,
    backfill_from_date       date,
    backfill_to_date         date,

    validation_status        varchar(30)   not null default 'PENDING',
    validation_errors        array,
    processed_status         varchar(30)   not null default 'PENDING',

    created_at               timestamp_ntz not null default current_timestamp(),

    constraint PK_INGESTION_WORK primary key (work_record_id)
)
comment = 'Transient validation buffer used before routing records to RAW or REJECT';

select
    table_type,
    table_schema,
    table_name,
    row_count
from DBT_MINI_PROJECT.information_schema.tables
where table_schema = 'CONTROL'
  and table_name = 'INGESTION_WORK';