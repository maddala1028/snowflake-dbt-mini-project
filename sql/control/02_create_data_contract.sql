/*==============================================================================
  Script: 02_create_data_contract.sql
  Purpose: Store versioned ingestion configuration and validation contracts.
==============================================================================*/

use database DBT_MINI_PROJECT;
use schema CONTROL;

create table if not exists  DBT_MINI_PROJECT.CONTROL.DATA_CONTRACT
(
    contract_id              number autoincrement start 1 increment 1,
    entity_name              varchar(100)  not null,
    contract_version         varchar(30)   not null,
    contract_description     varchar(500),

    source_system            varchar(100)  not null,
    stage_name               varchar(300)  not null,
    stage_path               varchar(500)  not null,
    file_type                varchar(20)   not null,
    file_pattern             varchar(500),
    file_format_name         varchar(300),

    raw_target_table         varchar(300)  not null,

    field_mapping            variant       not null,
    required_fields          array         not null,
    primary_key_fields       array         not null,
    validation_rules         variant,

    duplicate_check_enabled  boolean       not null default true,
    content_hash_fields      array,
    load_order               number        not null default 1,

    is_active                boolean       not null default true,
    effective_from           timestamp_ntz not null default current_timestamp(),
    effective_to             timestamp_ntz,

    created_at               timestamp_ntz not null default current_timestamp(),
    created_by               varchar(100)  not null default current_user(),
    updated_at               timestamp_ntz,
    updated_by               varchar(100),

    constraint PK_DATA_CONTRACT primary key (contract_id)
)
comment = 'Versioned metadata and validation rules for reusable ingestion';

