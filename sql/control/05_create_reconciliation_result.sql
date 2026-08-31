/*==============================================================================
  Script: 05_create_reconciliation_result.sql
  Purpose: Store file-level and batch-level reconciliation outcomes.
==============================================================================*/

create table if not exists DBT_MINI_PROJECT.AUDIT.RECONCILIATION_RESULT
(
    reconciliation_id       number autoincrement start 1 increment 1,
    batch_id                 varchar(100)  not null,
    file_load_id             number,
    entity_name              varchar(100)  not null,

    reconciliation_level     varchar(20)   not null,
    reconciliation_rule      varchar(1000) not null,

    source_row_count         number        not null default 0,
    loaded_row_count         number        not null default 0,
    rejected_row_count       number        not null default 0,
    duplicate_row_count      number        not null default 0,

    accounted_row_count      number        not null default 0,
    variance_count           number        not null default 0,
    tolerance_count          number        not null default 0,

    reconciliation_status    varchar(30)   not null,
    result_details           variant,

    checked_at               timestamp_ntz not null default current_timestamp(),
    checked_by               varchar(100)  not null default current_user(),

    constraint PK_RECONCILIATION_RESULT primary key (reconciliation_id)
)
comment = 'File and batch record-count reconciliation results';

select
    table_catalog,
    table_schema,
    table_name,
    row_count
from DBT_MINI_PROJECT.information_schema.tables
where table_schema = 'AUDIT'
  and table_name = 'RECONCILIATION_RESULT';