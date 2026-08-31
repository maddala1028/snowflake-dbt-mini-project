{{ config(
    materialized = 'incremental',
    incremental_strategy = 'merge',
    unique_key = 'customer_id',
    on_schema_change = 'append_new_columns',
    tags = ['silver', 'customers']
) }}

with source_data as (

    select
        customer_id,
        customer_name,
        email,
        city,
        customer_status,
        created_at,
        updated_at,

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
        

    from {{ ref('stg_customers') }}

    {% if is_incremental() %}

        where load_timestamp >= dateadd(
            day,
            -3,
            (
                select coalesce(
                    max(load_timestamp),
                    '1900-01-01'::timestamp_ntz
                )
                from {{ this }}
            )
        )

    {% endif %}

),

ranked as (

    select
        *,
        row_number() over (
            partition by customer_id
            order by
                coalesce(updated_at, created_at, load_timestamp) desc,
                load_timestamp desc,
                file_last_modified desc,
                ingestion_record_id desc
        ) as row_num

    from source_data

),

deduplicated as (

    select
        * exclude (row_num)

    from ranked
    where row_num = 1

),

changed_records as (

    select source.*

    from deduplicated as source

    {% if is_incremental() %}

        left join {{ this }} as target
            on source.customer_id = target.customer_id

        where target.customer_id is null
           or coalesce(source.record_hash, '') <>
              coalesce(target.record_hash, '')

    {% endif %}

)

select *
from changed_records