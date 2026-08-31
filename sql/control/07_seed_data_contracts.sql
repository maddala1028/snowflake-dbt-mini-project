USE ROLE DBT_ROLE;
USE WAREHOUSE DBT_WH;
USE DATABASE DBT_MINI_PROJECT;
USE SCHEMA RAW;
/*==============================================================================
  Script: 07_seed_data_contracts.sql
  Purpose: Register versioned contracts for ingestion entities.
==============================================================================*/

merge into DBT_MINI_PROJECT.CONTROL.DATA_CONTRACT as target

using
(
    select
        'CUSTOMERS'                                             as entity_name,
        '1.0'                                                   as contract_version,
        'Customer CSV ingestion contract'                       as contract_description,
        'S3'                                                    as source_system,

        'DBT_MINI_PROJECT.DBT_MINI_DEV.S3_DBT_MINI_STAGE'       as stage_name,
        'customers/'                                            as stage_path,
        'CSV'                                                   as file_type,
        '.*[.]csv'                                              as file_pattern,
        'DBT_MINI_PROJECT.DBT_MINI_DEV.CSV_FILE_FORMAT'         as file_format_name,

        'DBT_MINI_PROJECT.RAW.RAW_CUSTOMERS'                    as raw_target_table,

        object_construct(
            'customer_id',     '$1',
            'customer_name',   '$2',
            'email',           '$3',
            'city',            '$4',
            'customer_status', '$5',
            'created_at',      '$6',
            'updated_at',      '$7'
        )                                                       as field_mapping,

        array_construct(
            'customer_id',
            'customer_name',
            'email',
            'customer_status',
            'created_at'
        )                                                       as required_fields,

        array_construct('customer_id')                          as primary_key_fields,

        object_construct(
            'customer_status',
            object_construct(
                'rule_type', 'ACCEPTED_VALUES',
                'values', array_construct('ACTIVE', 'INACTIVE')
            ),
            'email',
            object_construct(
                'rule_type', 'REGEX',
                'pattern', '^[^@ ]+@[^@ ]+[.][^@ ]+$'
            )
        )                                                       as validation_rules,

        true                                                    as duplicate_check_enabled,

        array_construct(
            'customer_id',
            'customer_name',
            'email',
            'city',
            'customer_status',
            'created_at',
            'updated_at'
        )                                                       as content_hash_fields,

        1                                                       as load_order
) as source

on  target.entity_name = source.entity_name
and target.contract_version = source.contract_version

when matched then update set
    contract_description    = source.contract_description,
    source_system           = source.source_system,
    stage_name              = source.stage_name,
    stage_path              = source.stage_path,
    file_type               = source.file_type,
    file_pattern            = source.file_pattern,
    file_format_name        = source.file_format_name,
    raw_target_table        = source.raw_target_table,
    field_mapping           = source.field_mapping,
    required_fields         = source.required_fields,
    primary_key_fields      = source.primary_key_fields,
    validation_rules        = source.validation_rules,
    duplicate_check_enabled = source.duplicate_check_enabled,
    content_hash_fields     = source.content_hash_fields,
    load_order              = source.load_order,
    is_active               = true,
    effective_to            = null,
    updated_at              = current_timestamp(),
    updated_by              = current_user()

when not matched then insert
(
    entity_name,
    contract_version,
    contract_description,
    source_system,
    stage_name,
    stage_path,
    file_type,
    file_pattern,
    file_format_name,
    raw_target_table,
    field_mapping,
    required_fields,
    primary_key_fields,
    validation_rules,
    duplicate_check_enabled,
    content_hash_fields,
    load_order
)
values
(
    source.entity_name,
    source.contract_version,
    source.contract_description,
    source.source_system,
    source.stage_name,
    source.stage_path,
    source.file_type,
    source.file_pattern,
    source.file_format_name,
    source.raw_target_table,
    source.field_mapping,
    source.required_fields,
    source.primary_key_fields,
    source.validation_rules,
    source.duplicate_check_enabled,
    source.content_hash_fields,
    source.load_order
);

merge into DBT_MINI_PROJECT.CONTROL.DATA_CONTRACT as target

using
(
    select
        'APPLICATIONS'                                          as entity_name,
        '1.0'                                                   as contract_version,
        'Application JSON ingestion contract'                   as contract_description,
        'S3'                                                    as source_system,

        'DBT_MINI_PROJECT.DBT_MINI_DEV.S3_DBT_MINI_STAGE'       as stage_name,
        'applications/'                                         as stage_path,
        'JSON'                                                  as file_type,
        '.*[.]json'                                             as file_pattern,
        'DBT_MINI_PROJECT.DBT_MINI_DEV.JSON_FILE_FORMAT'        as file_format_name,

        'DBT_MINI_PROJECT.RAW.RAW_APPLICATIONS'                 as raw_target_table,

        object_construct(
            'application_id',     'application_id',
            'customer_id',        'customer_id',
            'application_status', 'application_status',
            'application_date',   'application_date',
            'requested_amount',   'requested_amount',
            'decision_date',      'decision_date'
        )                                                       as field_mapping,

        array_construct(
            'application_id',
            'customer_id',
            'application_status',
            'application_date',
            'requested_amount'
        )                                                       as required_fields,

        array_construct('application_id')                       as primary_key_fields,

        object_construct(
            'application_status',
            object_construct(
                'rule_type', 'ACCEPTED_VALUES',
                'values', array_construct(
                    'SUBMITTED',
                    'UNDER_REVIEW',
                    'APPROVED',
                    'REJECTED'
                )
            ),
            'requested_amount',
            object_construct(
                'rule_type', 'GREATER_THAN',
                'value', 0
            )
        )                                                       as validation_rules,

        true                                                    as duplicate_check_enabled,

        array_construct(
            'application_id',
            'customer_id',
            'application_status',
            'application_date',
            'requested_amount',
            'decision_date'
        )                                                       as content_hash_fields,

        2                                                       as load_order
) as source

on  target.entity_name = source.entity_name
and target.contract_version = source.contract_version

when matched then update set
    contract_description    = source.contract_description,
    source_system           = source.source_system,
    stage_name              = source.stage_name,
    stage_path              = source.stage_path,
    file_type               = source.file_type,
    file_pattern            = source.file_pattern,
    file_format_name        = source.file_format_name,
    raw_target_table        = source.raw_target_table,
    field_mapping           = source.field_mapping,
    required_fields         = source.required_fields,
    primary_key_fields      = source.primary_key_fields,
    validation_rules        = source.validation_rules,
    duplicate_check_enabled = source.duplicate_check_enabled,
    content_hash_fields     = source.content_hash_fields,
    load_order              = source.load_order,
    is_active               = true,
    effective_to            = null,
    updated_at              = current_timestamp(),
    updated_by              = current_user()

when not matched then insert
(
    entity_name,
    contract_version,
    contract_description,
    source_system,
    stage_name,
    stage_path,
    file_type,
    file_pattern,
    file_format_name,
    raw_target_table,
    field_mapping,
    required_fields,
    primary_key_fields,
    validation_rules,
    duplicate_check_enabled,
    content_hash_fields,
    load_order
)
values
(
    source.entity_name,
    source.contract_version,
    source.contract_description,
    source.source_system,
    source.stage_name,
    source.stage_path,
    source.file_type,
    source.file_pattern,
    source.file_format_name,
    source.raw_target_table,
    source.field_mapping,
    source.required_fields,
    source.primary_key_fields,
    source.validation_rules,
    source.duplicate_check_enabled,
    source.content_hash_fields,
    source.load_order
);

-- ============================================================================
-- PAYMENTS CONTRACT
-- ============================================================================

merge into DBT_MINI_PROJECT.CONTROL.DATA_CONTRACT as target

using
(
    select
        'PAYMENTS'                                              as entity_name,
        '1.0'                                                   as contract_version,
        'Payment Parquet ingestion contract'                    as contract_description,
        'S3'                                                    as source_system,

        'DBT_MINI_PROJECT.DBT_MINI_DEV.S3_DBT_MINI_STAGE'       as stage_name,
        'payments/'                                             as stage_path,
        'PARQUET'                                               as file_type,
        '.*[.]parquet'                                          as file_pattern,
        'DBT_MINI_PROJECT.DBT_MINI_DEV.PARQUET_FILE_FORMAT'     as file_format_name,

        'DBT_MINI_PROJECT.RAW.RAW_PAYMENTS'                     as raw_target_table,

        object_construct(
            'payment_id',     'payment_id',
            'application_id', 'application_id',
            'payment_amount', 'payment_amount',
            'payment_status', 'payment_status',
            'payment_date',   'payment_date',
            'payment_method', 'payment_method'
        )                                                       as field_mapping,

        array_construct(
            'payment_id',
            'application_id',
            'payment_amount',
            'payment_status',
            'payment_date'
        )                                                       as required_fields,

        array_construct('payment_id')                           as primary_key_fields,

        object_construct(
            'payment_status',
            object_construct(
                'rule_type', 'ACCEPTED_VALUES',
                'values', array_construct(
                    'PENDING',
                    'COMPLETED',
                    'FAILED',
                    'REFUNDED'
                )
            ),
            'payment_amount',
            object_construct(
                'rule_type', 'GREATER_THAN',
                'value', 0
            )
        )                                                       as validation_rules,

        true                                                    as duplicate_check_enabled,

        array_construct(
            'payment_id',
            'application_id',
            'payment_amount',
            'payment_status',
            'payment_date',
            'payment_method'
        )                                                       as content_hash_fields,

        3                                                       as load_order
) as source

on  target.entity_name = source.entity_name
and target.contract_version = source.contract_version

when matched then update set
    contract_description    = source.contract_description,
    source_system           = source.source_system,
    stage_name              = source.stage_name,
    stage_path              = source.stage_path,
    file_type               = source.file_type,
    file_pattern            = source.file_pattern,
    file_format_name        = source.file_format_name,
    raw_target_table        = source.raw_target_table,
    field_mapping           = source.field_mapping,
    required_fields         = source.required_fields,
    primary_key_fields      = source.primary_key_fields,
    validation_rules        = source.validation_rules,
    duplicate_check_enabled = source.duplicate_check_enabled,
    content_hash_fields     = source.content_hash_fields,
    load_order              = source.load_order,
    is_active               = true,
    effective_to            = null,
    updated_at              = current_timestamp(),
    updated_by              = current_user()

when not matched then insert
(
    entity_name,
    contract_version,
    contract_description,
    source_system,
    stage_name,
    stage_path,
    file_type,
    file_pattern,
    file_format_name,
    raw_target_table,
    field_mapping,
    required_fields,
    primary_key_fields,
    validation_rules,
    duplicate_check_enabled,
    content_hash_fields,
    load_order
)
values
(
    source.entity_name,
    source.contract_version,
    source.contract_description,
    source.source_system,
    source.stage_name,
    source.stage_path,
    source.file_type,
    source.file_pattern,
    source.file_format_name,
    source.raw_target_table,
    source.field_mapping,
    source.required_fields,
    source.primary_key_fields,
    source.validation_rules,
    source.duplicate_check_enabled,
    source.content_hash_fields,
    source.load_order
);

