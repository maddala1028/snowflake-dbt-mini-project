create or replace procedure
DBT_MINI_PROJECT.PROCEDURES.SP_DISCOVER_ENTITY_FILES
(
    P_ENTITY_NAME       varchar,
    P_RUN_MODE         varchar,
    P_FORCE_RELOAD     boolean,
    P_BACKFILL_FROM    date,
    P_BACKFILL_TO      date
)
returns variant
language sql
execute as owner
as
$$
declare
    V_ENTITY_NAME       varchar;
    V_RUN_MODE          varchar;
    V_FORCE_RELOAD      boolean;
    V_BATCH_ID          varchar default uuid_string();

    V_CONTRACT_COUNT    number default 0;
    V_CONTRACT_ID       number;
    V_CONTRACT_VERSION  varchar;
    V_STAGE_NAME        varchar;
    V_STAGE_PATH        varchar;
    V_FILE_TYPE         varchar;
    V_FILE_PATTERN      varchar;

    V_FILES_DISCOVERED  number default 0;
    V_FILES_SELECTED    number default 0;
    V_FILES_SKIPPED     number default 0;

    V_ERROR_CODE        varchar;
    V_ERROR_MESSAGE     varchar;

begin
    /*----------------------------------------------------------------------
      1. Standardise inputs
    ----------------------------------------------------------------------*/

    V_ENTITY_NAME := upper(trim(P_ENTITY_NAME));
    V_RUN_MODE := upper(trim(P_RUN_MODE));
    V_FORCE_RELOAD := coalesce(P_FORCE_RELOAD, false);

    /*----------------------------------------------------------------------
      2. Validate inputs
    ----------------------------------------------------------------------*/

    if (
        V_ENTITY_NAME is null
        or V_ENTITY_NAME = ''
    ) then
        return object_construct(
            'status', 'FAILED',
            'error', 'Entity name must be supplied'
        );
    end if;

    if (
        V_RUN_MODE is null
        or V_RUN_MODE not in (
            'INCREMENTAL',
            'BACKFILL',
            'REPROCESS'
        )
    ) then
        return object_construct(
            'status', 'FAILED',
            'error', 'Invalid run mode',
            'allowed_values',
            array_construct(
                'INCREMENTAL',
                'BACKFILL',
                'REPROCESS'
            )
        );
    end if;

    if (
        V_RUN_MODE = 'BACKFILL'
        and (
            P_BACKFILL_FROM is null
            or P_BACKFILL_TO is null
        )
    ) then
        return object_construct(
            'status', 'FAILED',
            'error', 'BACKFILL requires both from and to dates'
        );
    end if;

    if (
        V_RUN_MODE = 'BACKFILL'
        and P_BACKFILL_FROM > P_BACKFILL_TO
    ) then
        return object_construct(
            'status', 'FAILED',
            'error', 'Backfill from date cannot be after backfill to date'
        );
    end if;

    /*----------------------------------------------------------------------
      3. Confirm exactly one active contract
    ----------------------------------------------------------------------*/

    select count(*)
    into :V_CONTRACT_COUNT
    from DBT_MINI_PROJECT.CONTROL.DATA_CONTRACT
    where entity_name = :V_ENTITY_NAME
      and is_active = true
      and current_timestamp() >= effective_from
      and (
          effective_to is null
          or current_timestamp() < effective_to
      );

    if (V_CONTRACT_COUNT <> 1) then
        return object_construct(
            'status', 'FAILED',
            'entity_name', V_ENTITY_NAME,
            'active_contract_count', V_CONTRACT_COUNT,
            'error', 'Expected exactly one active contract'
        );
    end if;

    /*----------------------------------------------------------------------
      4. Load active contract configuration
    ----------------------------------------------------------------------*/

    select
        contract_id,
        contract_version,
        stage_name,
        stage_path,
        file_type,
        file_pattern
    into
        :V_CONTRACT_ID,
        :V_CONTRACT_VERSION,
        :V_STAGE_NAME,
        :V_STAGE_PATH,
        :V_FILE_TYPE,
        :V_FILE_PATTERN
    from DBT_MINI_PROJECT.CONTROL.DATA_CONTRACT
    where entity_name = :V_ENTITY_NAME
      and is_active = true
      and current_timestamp() >= effective_from
      and (
          effective_to is null
          or current_timestamp() < effective_to
      );

    /*----------------------------------------------------------------------
      5. Start batch audit
    ----------------------------------------------------------------------*/

    insert into DBT_MINI_PROJECT.AUDIT.INGESTION_BATCH_AUDIT
    (
        batch_id,
        entity_name,
        contract_id,
        contract_version,
        run_mode,
        force_reload,
        backfill_from,
        backfill_to,
        batch_status
    )
    values
    (
        :V_BATCH_ID,
        :V_ENTITY_NAME,
        :V_CONTRACT_ID,
        :V_CONTRACT_VERSION,
        :V_RUN_MODE,
        :V_FORCE_RELOAD,
        :P_BACKFILL_FROM,
        :P_BACKFILL_TO,
        'DISCOVERING'
    );

    /*----------------------------------------------------------------------
      6. Register discovered files

      Idempotency:
      - Same previously loaded path: skip
      - Same checksum under another filename: skip
      - Force reload: select regardless of previous history
    ----------------------------------------------------------------------*/

    insert into DBT_MINI_PROJECT.AUDIT.FILE_LOAD_AUDIT
    (
        batch_id,
        entity_name,
        contract_id,
        contract_version,
        stage_name,
        stage_path,
        file_name,
        full_file_path,
        file_type,
        file_size_bytes,
        file_last_modified,
        file_etag,
        file_content_key,
        file_checksum,
        load_attempt_number,
        file_status,
        skip_reason
    )
    select
        :V_BATCH_ID,
        :V_ENTITY_NAME,
        :V_CONTRACT_ID,
        :V_CONTRACT_VERSION,
        listed.stage_name,
        :V_STAGE_PATH,
        listed.file_name,

        listed.stage_name
            || '/'
            || listed.relative_path,

        :V_FILE_TYPE,
        listed.file_size_bytes,
        listed.file_last_modified,
        listed.file_checksum,
        listed.file_checksum,
        listed.file_checksum,

        (
            select count(*) + 1
            from DBT_MINI_PROJECT.AUDIT.FILE_LOAD_AUDIT previous
            where previous.entity_name = :V_ENTITY_NAME
              and previous.full_file_path =
                    listed.stage_name
                    || '/'
                    || listed.relative_path
        ),

        case
            when :V_FORCE_RELOAD = true
                then 'SELECTED'

            when exists
            (
                select 1
                from DBT_MINI_PROJECT.AUDIT.FILE_LOAD_AUDIT previous
                where previous.entity_name = :V_ENTITY_NAME
                  and previous.file_status = 'LOADED'
                  and
                  (
                      previous.full_file_path =
                          listed.stage_name
                          || '/'
                          || listed.relative_path

                      or previous.file_checksum =
                          listed.file_checksum
                  )
            )
                then 'SKIPPED'

            else 'SELECTED'
        end,

        case
            when :V_FORCE_RELOAD = true
                then null

            when exists
            (
                select 1
                from DBT_MINI_PROJECT.AUDIT.FILE_LOAD_AUDIT previous
                where previous.entity_name = :V_ENTITY_NAME
                  and previous.file_status = 'LOADED'
                  and previous.full_file_path =
                        listed.stage_name
                        || '/'
                        || listed.relative_path
            )
                then 'FILE_ALREADY_LOADED'

            when exists
            (
                select 1
                from DBT_MINI_PROJECT.AUDIT.FILE_LOAD_AUDIT previous
                where previous.entity_name = :V_ENTITY_NAME
                  and previous.file_status = 'LOADED'
                  and previous.file_checksum =
                        listed.file_checksum
            )
                then 'DUPLICATE_FILE_CONTENT'

            else null
        end

    from DBT_MINI_PROJECT.CONTROL.V_STAGE_FILE_DIRECTORY listed

    where listed.stage_name = :V_STAGE_NAME
      and startswith(
          listed.relative_path,
          :V_STAGE_PATH
      )
      and regexp_like(
          listed.relative_path,
          :V_FILE_PATTERN
      );

    /*----------------------------------------------------------------------
      7. Calculate discovery totals
    ----------------------------------------------------------------------*/

    select
        count(*),
        count_if(file_status = 'SELECTED'),
        count_if(file_status = 'SKIPPED')
    into
        :V_FILES_DISCOVERED,
        :V_FILES_SELECTED,
        :V_FILES_SKIPPED
    from DBT_MINI_PROJECT.AUDIT.FILE_LOAD_AUDIT
    where batch_id = :V_BATCH_ID;

    /*----------------------------------------------------------------------
      8. Complete batch discovery audit
    ----------------------------------------------------------------------*/

    update DBT_MINI_PROJECT.AUDIT.INGESTION_BATCH_AUDIT
    set
        batch_status = 'DISCOVERED',
        files_discovered = :V_FILES_DISCOVERED,
        files_selected = :V_FILES_SELECTED,
        files_skipped = :V_FILES_SKIPPED,
        updated_at = current_timestamp()
    where batch_id = :V_BATCH_ID;

    /*----------------------------------------------------------------------
      9. Return discovery result
    ----------------------------------------------------------------------*/

    return object_construct(
        'status', 'DISCOVERED',
        'batch_id', V_BATCH_ID,
        'entity_name', V_ENTITY_NAME,
        'contract_id', V_CONTRACT_ID,
        'contract_version', V_CONTRACT_VERSION,
        'files_discovered', V_FILES_DISCOVERED,
        'files_selected', V_FILES_SELECTED,
        'files_skipped', V_FILES_SKIPPED
    );

/*----------------------------------------------------------------------
  10. Exception handling
----------------------------------------------------------------------*/

exception
    when other then
        V_ERROR_CODE := sqlstate;
        V_ERROR_MESSAGE := sqlerrm;

        update DBT_MINI_PROJECT.AUDIT.INGESTION_BATCH_AUDIT
        set
            batch_status = 'FAILED',
            end_timestamp = current_timestamp(),
            error_code = :V_ERROR_CODE,
            error_message = :V_ERROR_MESSAGE,
            updated_at = current_timestamp()
        where batch_id = :V_BATCH_ID;

        return object_construct(
            'status', 'FAILED',
            'batch_id', V_BATCH_ID,
            'entity_name', V_ENTITY_NAME,
            'sqlstate', V_ERROR_CODE,
            'error', V_ERROR_MESSAGE
        );
end;
$$;