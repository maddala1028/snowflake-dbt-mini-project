with source_data as (

    select *
    from {{ source('raw', 'raw_applications') }}

),

typed as (

    select
        trim(raw_record:application_id::varchar)
            as application_id,

        trim(raw_record:customer_id::varchar)
            as customer_id,

        upper(trim(raw_record:application_status::varchar))
            as application_status,

        try_to_date(raw_record:application_date::varchar)
            as application_date,

        try_to_decimal(
            raw_record:requested_amount::varchar,
            18,
            2
        ) as requested_amount,

        try_to_date(raw_record:decision_date::varchar)
            as decision_date,

        -- Ingestion lineage and audit metadata
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