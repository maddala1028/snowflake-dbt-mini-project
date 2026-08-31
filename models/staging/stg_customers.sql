{{ config(
    materialized = 'view',
    tags = ['staging', 'customers']
) }}

with source_data as (

    select *
    from {{ source('raw', 'raw_customers') }}

),

typed as (

    select
        trim(raw_record:customer_id::varchar)           as customer_id,
        trim(raw_record:customer_name::varchar)         as customer_name,
        lower(trim(raw_record:email::varchar))           as email,
        initcap(trim(raw_record:city::varchar))          as city,
        upper(trim(raw_record:customer_status::varchar)) as customer_status,

        try_to_timestamp_ntz(
            raw_record:created_at::varchar
        )                                                as created_at,

        try_to_timestamp_ntz(
            raw_record:updated_at::varchar
        )                                                as updated_at,

        ingestion_record_id,
        entity_name,
        record_hash,
        source_system,
        source_object,
        file_type,
        file_name,
        file_row_number,
        file_content_key,
        file_last_modified,
        scan_start_time,
        load_timestamp,
        batch_id,
        run_mode,
        contract_version,
        source_date,
        backfill_from_date,
        backfill_to_date

    from source_data

)

select *
from typed