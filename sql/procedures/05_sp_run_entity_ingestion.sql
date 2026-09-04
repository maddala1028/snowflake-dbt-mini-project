create or replace procedure DBT_MINI_PROJECT.PROCEDURES.SP_RUN_ENTITY_INGESTION(
    P_ENTITY_NAME varchar,
    P_RUN_MODE varchar,
    P_FORCE_RELOAD boolean,
    P_BACKFILL_FROM date,
    P_BACKFILL_TO date
)
returns variant
language sql
execute as owner
as
$$
declare
    V_ENTITY_NAME        varchar;
    V_BATCH_ID           varchar;
    V_FILES_SELECTED     number default 0;

    V_DISCOVERY_STATUS   varchar;
    V_STAGE_STATUS       varchar;
    V_VALIDATION_STATUS  varchar;
    V_LOAD_STATUS        varchar;

    V_DISCOVERY_RESULT   variant;
    V_STAGE_RESULT       variant;
    V_VALIDATION_RESULT  variant;
    V_LOAD_RESULT        variant;

    V_ERROR_CODE         varchar;
    V_ERROR_MESSAGE      varchar;
begin

    /*----------------------------------------------------------
      1. Validate orchestration parameters
    ----------------------------------------------------------*/
    V_ENTITY_NAME := upper(trim(P_ENTITY_NAME));

    if (V_ENTITY_NAME is null or V_ENTITY_NAME = '') then
        return object_construct(
            'status', 'FAILED',
            'step', 'PARAMETER_VALIDATION',
            'error_code', 'INVALID_ENTITY_NAME',
            'error', 'P_ENTITY_NAME must not be null or empty'
        );
    end if;

    if (
        P_BACKFILL_FROM is not null
        and P_BACKFILL_TO is not null
        and P_BACKFILL_FROM > P_BACKFILL_TO
    ) then
        return object_construct(
            'status', 'FAILED',
            'step', 'PARAMETER_VALIDATION',
            'entity_name', V_ENTITY_NAME,
            'error_code', 'INVALID_BACKFILL_RANGE',
            'error', 'P_BACKFILL_FROM cannot be later than P_BACKFILL_TO'
        );
    end if;

    /*----------------------------------------------------------
      2. Discover files and create batch/file audit records
    ----------------------------------------------------------*/
    call DBT_MINI_PROJECT.PROCEDURES.SP_DISCOVER_ENTITY_FILES(
        :V_ENTITY_NAME,
        :P_RUN_MODE,
        :P_FORCE_RELOAD,
        :P_BACKFILL_FROM,
        :P_BACKFILL_TO
    ) into :V_DISCOVERY_RESULT;

    select
        :V_DISCOVERY_RESULT:status::varchar,
        :V_DISCOVERY_RESULT:batch_id::varchar,
        coalesce(
            :V_DISCOVERY_RESULT:files_selected::number,
            0
        )
    into
        :V_DISCOVERY_STATUS,
        :V_BATCH_ID,
        :V_FILES_SELECTED;

    if (V_DISCOVERY_STATUS = 'FAILED') then
        return object_construct(
            'status', 'FAILED',
            'step', 'DISCOVERY',
            'entity_name', V_ENTITY_NAME,
            'batch_id', V_BATCH_ID,
            'discovery_result', V_DISCOVERY_RESULT
        );
    end if;

    /*
      A successful idempotency check may find no new files.
      That is a successful no-work outcome, not a pipeline failure.
    */
    if (V_FILES_SELECTED = 0) then
        update DBT_MINI_PROJECT.AUDIT.INGESTION_BATCH_AUDIT
           set batch_status = 'SKIPPED',
               end_timestamp = current_timestamp(),
               updated_at = current_timestamp()
         where batch_id = :V_BATCH_ID
           and batch_status = 'DISCOVERED';

        return object_construct(
            'status', 'SKIPPED',
            'step', 'DISCOVERY',
            'entity_name', V_ENTITY_NAME,
            'batch_id', V_BATCH_ID,
            'reason', 'No new files were selected for ingestion',
            'discovery_result', V_DISCOVERY_RESULT
        );
    end if;

    /*
      The current staging procedure intentionally supports one
      selected file per entity batch.
    */
    if (V_FILES_SELECTED <> 1) then
        return object_construct(
            'status', 'FAILED',
            'step', 'DISCOVERY',
            'entity_name', V_ENTITY_NAME,
            'batch_id', V_BATCH_ID,
            'error_code', 'UNSUPPORTED_FILE_COUNT',
            'error',
                'SP_STAGE_SELECTED_FILES currently requires exactly one selected file',
            'files_selected', V_FILES_SELECTED,
            'discovery_result', V_DISCOVERY_RESULT
        );
    end if;

    /*----------------------------------------------------------
      3. Parse selected file into INGESTION_WORK
    ----------------------------------------------------------*/
    call DBT_MINI_PROJECT.PROCEDURES.SP_STAGE_SELECTED_FILES(
        :V_BATCH_ID
    ) into :V_STAGE_RESULT;

    select
        :V_STAGE_RESULT:status::varchar
    into
        :V_STAGE_STATUS;

    if (V_STAGE_STATUS <> 'STAGED') then
        return object_construct(
            'status', 'FAILED',
            'step', 'STAGING',
            'entity_name', V_ENTITY_NAME,
            'batch_id', V_BATCH_ID,
            'discovery_result', V_DISCOVERY_RESULT,
            'stage_result', V_STAGE_RESULT
        );
    end if;

    /*----------------------------------------------------------
      4. Apply metadata-driven contract validation
    ----------------------------------------------------------*/
    call DBT_MINI_PROJECT.PROCEDURES.SP_VALIDATE_WORK_BATCH(
        :V_BATCH_ID
    ) into :V_VALIDATION_RESULT;

    select
        :V_VALIDATION_RESULT:status::varchar
    into
        :V_VALIDATION_STATUS;

    if (V_VALIDATION_STATUS <> 'VALIDATED') then
        return object_construct(
            'status', 'FAILED',
            'step', 'VALIDATION',
            'entity_name', V_ENTITY_NAME,
            'batch_id', V_BATCH_ID,
            'discovery_result', V_DISCOVERY_RESULT,
            'stage_result', V_STAGE_RESULT,
            'validation_result', V_VALIDATION_RESULT
        );
    end if;

    /*----------------------------------------------------------
      5. Load valid records, skip duplicates and reconcile
    ----------------------------------------------------------*/
    call DBT_MINI_PROJECT.PROCEDURES.SP_LOAD_VALIDATED_BATCH(
        :V_BATCH_ID
    ) into :V_LOAD_RESULT;

    select
        :V_LOAD_RESULT:status::varchar
    into
        :V_LOAD_STATUS;

    if (V_LOAD_STATUS <> 'COMPLETED') then
        return object_construct(
            'status', 'FAILED',
            'step', 'LOAD_AND_RECONCILIATION',
            'entity_name', V_ENTITY_NAME,
            'batch_id', V_BATCH_ID,
            'discovery_result', V_DISCOVERY_RESULT,
            'stage_result', V_STAGE_RESULT,
            'validation_result', V_VALIDATION_RESULT,
            'load_result', V_LOAD_RESULT
        );
    end if;

    /*----------------------------------------------------------
      6. Return one end-to-end orchestration result
    ----------------------------------------------------------*/
    return object_construct(
        'status', 'COMPLETED',
        'entity_name', V_ENTITY_NAME,
        'batch_id', V_BATCH_ID,
        'run_mode', P_RUN_MODE,
        'force_reload', P_FORCE_RELOAD,
        'discovery', V_DISCOVERY_RESULT,
        'staging', V_STAGE_RESULT,
        'validation', V_VALIDATION_RESULT,
        'load_and_reconciliation', V_LOAD_RESULT
    );

exception
    when other then
        V_ERROR_CODE := SQLSTATE;
        V_ERROR_MESSAGE := SQLERRM;

        /*
          Child procedures maintain their own audit failure states.
          This update covers an unexpected wrapper-level failure.
        */
        update DBT_MINI_PROJECT.AUDIT.INGESTION_BATCH_AUDIT
           set batch_status = 'FAILED',
               end_timestamp = current_timestamp(),
               error_code = :V_ERROR_CODE,
               error_message = :V_ERROR_MESSAGE,
               updated_at = current_timestamp()
         where batch_id = :V_BATCH_ID
           and batch_status not in (
               'COMPLETED',
               'FAILED',
               'SKIPPED'
           );

        return object_construct(
            'status', 'FAILED',
            'step', 'ORCHESTRATION',
            'entity_name', V_ENTITY_NAME,
            'batch_id', V_BATCH_ID,
            'error_code', V_ERROR_CODE,
            'error', V_ERROR_MESSAGE,
            'discovery_result', V_DISCOVERY_RESULT,
            'stage_result', V_STAGE_RESULT,
            'validation_result', V_VALIDATION_RESULT,
            'load_result', V_LOAD_RESULT
        );
end;
$$;
