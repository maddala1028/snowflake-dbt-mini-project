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
        source_date
        

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

-- Include the existing Silver version for every incoming customer before
-- ranking. An older arrival therefore cannot displace a newer stored version,
-- even when that stored version is outside the three-day RAW lookback.
-- Exact ordering ties retain the existing target. Nulls sort last explicitly.
version_candidates as (

    select source_data.*, 0 as existing_version_priority
    from source_data

    {% if is_incremental() %}

    union all

    select
        target.customer_id,
        target.customer_name,
        target.email,
        target.city,
        target.customer_status,
        target.created_at,
        target.updated_at,
        target.ingestion_record_id,
        target.entity_name,
        target.record_hash,
        target.source_system,
        target.source_object,
        target.file_type,
        target.file_name,
        target.file_row_number,
        target.file_content_key,
        target.file_last_modified,
        target.scan_start_time,
        target.load_timestamp,
        target.batch_id,
        target.run_mode,
        target.contract_version,
        target.source_date,
        1 as existing_version_priority
    from {{ this }} as target
    where exists (
        select 1
        from source_data as incoming
        where incoming.customer_id = target.customer_id
    )

    {% endif %}

),

ranked as (

    select
        *,
        row_number() over (
            partition by customer_id
            order by
                coalesce(updated_at, created_at, load_timestamp) desc nulls last,
                load_timestamp desc nulls last,
                file_last_modified desc nulls last,
                ingestion_record_id desc nulls last,
                existing_version_priority desc
        ) as row_num

    from version_candidates

),

deduplicated as (

    select
        * exclude (row_num, existing_version_priority)

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
