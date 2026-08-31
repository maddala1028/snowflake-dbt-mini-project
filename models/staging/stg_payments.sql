with source_data as (

    select *
    from {{ source('raw', 'raw_payments') }}

),

typed as (

    select
        trim(raw_record:payment_id::varchar)
            as payment_id,

        trim(raw_record:application_id::varchar)
            as application_id,

        try_to_decimal(
            raw_record:payment_amount::varchar,
            18,
            2
        ) as payment_amount,

        upper(trim(raw_record:payment_status::varchar))
            as payment_status,

        try_to_timestamp_ntz(
            raw_record:payment_date::varchar
        ) as payment_date,

        trim(raw_record:payment_method::varchar)
            as payment_method,

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