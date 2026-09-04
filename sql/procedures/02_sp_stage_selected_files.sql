create or replace procedure
DBT_MINI_PROJECT.PROCEDURES.SP_STAGE_SELECTED_FILES
(
    P_BATCH_ID varchar
)
returns variant
language sql
execute as owner
as
$$
declare
    V_BATCH_COUNT          number default 0;
    V_SELECTED_FILES       number default 0;

    V_ENTITY_NAME          varchar;
    V_CONTRACT_ID          number;
    V_CONTRACT_VERSION     varchar;
    V_RUN_MODE             varchar;
    V_BACKFILL_FROM        date;
    V_BACKFILL_TO          date;

    V_SOURCE_SYSTEM        varchar;
    V_STAGE_NAME           varchar;
    V_STAGE_PATH           varchar;
    V_FILE_TYPE            varchar;
    V_FILE_FORMAT_NAME     varchar;

    V_CURRENT_FILE_ID      number;
    V_CURRENT_FILE_NAME    varchar;
    V_CURRENT_CHECKSUM     varchar;

    V_RAW_EXPRESSION       varchar;
    V_STAGE_LOCATION       varchar;
    V_BACKFILL_FROM_SQL    varchar;
    V_BACKFILL_TO_SQL      varchar;
    V_INSERT_SQL           varchar;

    V_FILE_ROW_COUNT       number default 0;
    V_TOTAL_ROW_COUNT      number default 0;
    V_FILES_STAGED         number default 0;
    V_FILES_FAILED         number default 0;

    V_ERROR_CODE           varchar;
    V_ERROR_MESSAGE        varchar;

begin
    /* Validate the batch */
    select count(*)
    into :V_BATCH_COUNT
    from DBT_MINI_PROJECT.AUDIT.INGESTION_BATCH_AUDIT
    where batch_id = :P_BATCH_ID
      and batch_status = 'DISCOVERED';

    if (V_BATCH_COUNT <> 1) then
        return object_construct(
            'status', 'FAILED',
            'batch_id', P_BATCH_ID,
            'error', 'Expected one DISCOVERED batch'
        );
    end if;

    /* Load batch and contract configuration */
    select
        batch.entity_name,
        batch.contract_id,
        batch.contract_version,
        batch.run_mode,
        to_date(batch.backfill_from),
        to_date(batch.backfill_to),
        contract.source_system,
        contract.stage_name,
        contract.stage_path,
        contract.file_type,
        contract.file_format_name
    into
        :V_ENTITY_NAME,
        :V_CONTRACT_ID,
        :V_CONTRACT_VERSION,
        :V_RUN_MODE,
        :V_BACKFILL_FROM,
        :V_BACKFILL_TO,
        :V_SOURCE_SYSTEM,
        :V_STAGE_NAME,
        :V_STAGE_PATH,
        :V_FILE_TYPE,
        :V_FILE_FORMAT_NAME
    from DBT_MINI_PROJECT.AUDIT.INGESTION_BATCH_AUDIT batch
    join DBT_MINI_PROJECT.CONTROL.DATA_CONTRACT contract
      on batch.contract_id = contract.contract_id
    where batch.batch_id = :P_BATCH_ID;

    select count(*)
    into :V_SELECTED_FILES
    from DBT_MINI_PROJECT.AUDIT.FILE_LOAD_AUDIT
    where batch_id = :P_BATCH_ID
      and file_status = 'SELECTED';

    if (V_SELECTED_FILES = 0) then
        update DBT_MINI_PROJECT.AUDIT.INGESTION_BATCH_AUDIT
        set
            batch_status = 'SKIPPED',
            end_timestamp = current_timestamp(),
            updated_at = current_timestamp()
        where batch_id = :P_BATCH_ID;

        return object_construct(
            'status', 'SKIPPED',
            'batch_id', P_BATCH_ID,
            'entity_name', V_ENTITY_NAME,
            'reason', 'No files were selected'
        );
    end if;

    /* Ensure retrying the batch does not duplicate work records */
    delete from DBT_MINI_PROJECT.CONTROL.INGESTION_WORK
    where batch_id = :P_BATCH_ID;

    update DBT_MINI_PROJECT.AUDIT.INGESTION_BATCH_AUDIT
    set
        batch_status = 'STAGING',
        updated_at = current_timestamp()
    where batch_id = :P_BATCH_ID;

    V_STAGE_LOCATION :=
        '@' || V_STAGE_NAME || '/' || V_STAGE_PATH;

    if (V_FILE_TYPE = 'CSV') then
        V_RAW_EXPRESSION :=
            'object_construct_keep_null('
            || '''customer_id'', $1, '
            || '''customer_name'', $2, '
            || '''email'', $3, '
            || '''city'', $4, '
            || '''customer_status'', $5, '
            || '''created_at'', $6, '
            || '''updated_at'', $7'
            || ')';
    elseif (V_FILE_TYPE in ('JSON', 'PARQUET')) then
        V_RAW_EXPRESSION := '$1';
    else
        return object_construct(
            'status', 'FAILED',
            'batch_id', P_BATCH_ID,
            'error', 'Unsupported file type',
            'file_type', V_FILE_TYPE
        );
    end if;

    if (V_BACKFILL_FROM is null) then
        V_BACKFILL_FROM_SQL := 'null';
    else
        V_BACKFILL_FROM_SQL :=
            '''' || to_char(V_BACKFILL_FROM, 'YYYY-MM-DD') || '''::date';
    end if;

    if (V_BACKFILL_TO is null) then
        V_BACKFILL_TO_SQL := 'null';
    else
        V_BACKFILL_TO_SQL :=
            '''' || to_char(V_BACKFILL_TO, 'YYYY-MM-DD') || '''::date';
    end if;

    /* Stage every selected file */
    for FILE_RECORD in
    (
        select
            file_load_id,
            file_name,
            file_checksum
        from DBT_MINI_PROJECT.AUDIT.FILE_LOAD_AUDIT
        where batch_id = :P_BATCH_ID
          and file_status = 'SELECTED'
        order by file_load_id
    )
    do
        V_CURRENT_FILE_ID := FILE_RECORD.FILE_LOAD_ID;
        V_CURRENT_FILE_NAME := FILE_RECORD.FILE_NAME;
        V_CURRENT_CHECKSUM := FILE_RECORD.FILE_CHECKSUM;

        update DBT_MINI_PROJECT.AUDIT.FILE_LOAD_AUDIT
        set
            file_status = 'LOADING',
            load_start_timestamp = current_timestamp(),
            updated_at = current_timestamp()
        where file_load_id = :V_CURRENT_FILE_ID;

        V_INSERT_SQL :=
            'insert into DBT_MINI_PROJECT.CONTROL.INGESTION_WORK '
            || '('
            || 'batch_id, file_load_id, entity_name, '
            || 'contract_id, contract_version, '
            || 'ingestion_record_id, raw_record, record_hash, '
            || 'source_system, source_object, file_type, '
            || 'file_name, file_row_number, file_content_key, '
            || 'file_last_modified, scan_start_time, load_timestamp, '
            || 'run_mode, source_date, '
            || 'backfill_from_date, backfill_to_date, '
            || 'validation_status, validation_errors, processed_status'
            || ') '
            || 'select '
            || '''' || P_BATCH_ID || ''', '
            || V_CURRENT_FILE_ID || ', '
            || '''' || V_ENTITY_NAME || ''', '
            || V_CONTRACT_ID || ', '
            || '''' || V_CONTRACT_VERSION || ''', '

            || 'sha2(concat('
            || '''' || P_BATCH_ID || '|'', '
            || 'metadata$filename, ''|'', metadata$file_row_number'
            || '), 256), '

            || V_RAW_EXPRESSION || ', '
            || 'sha2(to_json(' || V_RAW_EXPRESSION || '), 256), '

            || '''' || V_SOURCE_SYSTEM || ''', '
            || 'metadata$filename, '
            || '''' || V_FILE_TYPE || ''', '
            || 'metadata$filename, '
            || 'metadata$file_row_number, '
            || '''' || V_CURRENT_CHECKSUM || ''', '
            || 'metadata$file_last_modified::timestamp_ntz, '
            || 'metadata$start_scan_time, '
            || 'current_timestamp(), '
            || '''' || V_RUN_MODE || ''', '
            || 'to_date(metadata$file_last_modified), '
            || V_BACKFILL_FROM_SQL || ', '
            || V_BACKFILL_TO_SQL || ', '
            || '''PENDING'', '
            || 'array_construct(), '
            || '''PENDING'' '

            || 'from '
            || V_STAGE_LOCATION
            || ' (file_format => '''
            || V_FILE_FORMAT_NAME
            || ''') '

            || 'where regexp_substr('
            || 'metadata$filename, ''[^/]+$'''
            || ') = '''
            || replace(V_CURRENT_FILE_NAME, '''', '''''')
            || '''';

        execute immediate :V_INSERT_SQL;

        select count(*)
        into :V_FILE_ROW_COUNT
        from DBT_MINI_PROJECT.CONTROL.INGESTION_WORK
        where batch_id = :P_BATCH_ID
          and file_load_id = :V_CURRENT_FILE_ID;

        update DBT_MINI_PROJECT.AUDIT.FILE_LOAD_AUDIT
        set
            file_status = 'STAGED',
            source_row_count = :V_FILE_ROW_COUNT,
            load_end_timestamp = current_timestamp(),
            updated_at = current_timestamp()
        where file_load_id = :V_CURRENT_FILE_ID;

        V_TOTAL_ROW_COUNT :=
            V_TOTAL_ROW_COUNT + V_FILE_ROW_COUNT;

        V_FILES_STAGED :=
            V_FILES_STAGED + 1;
    end for;

    update DBT_MINI_PROJECT.AUDIT.INGESTION_BATCH_AUDIT
    set
        batch_status = 'STAGED',
        source_row_count = :V_TOTAL_ROW_COUNT,
        updated_at = current_timestamp()
    where batch_id = :P_BATCH_ID;

    return object_construct(
        'status', 'STAGED',
        'batch_id', P_BATCH_ID,
        'entity_name', V_ENTITY_NAME,
        'files_staged', V_FILES_STAGED,
        'rows_staged', V_TOTAL_ROW_COUNT
    );

exception
    when other then
        V_ERROR_CODE := sqlstate;
        V_ERROR_MESSAGE := sqlerrm;

        if (V_CURRENT_FILE_ID is not null) then
            update DBT_MINI_PROJECT.AUDIT.FILE_LOAD_AUDIT
            set
                file_status = 'FAILED',
                load_end_timestamp = current_timestamp(),
                error_code = :V_ERROR_CODE,
                error_message = :V_ERROR_MESSAGE,
                updated_at = current_timestamp()
            where file_load_id = :V_CURRENT_FILE_ID;
        end if;

        update DBT_MINI_PROJECT.AUDIT.INGESTION_BATCH_AUDIT
        set
            batch_status = 'FAILED',
            end_timestamp = current_timestamp(),
            files_failed = files_failed + 1,
            error_code = :V_ERROR_CODE,
            error_message = :V_ERROR_MESSAGE,
            updated_at = current_timestamp()
        where batch_id = :P_BATCH_ID;

        return object_construct(
            'status', 'FAILED',
            'batch_id', P_BATCH_ID,
            'entity_name', V_ENTITY_NAME,
            'file_load_id', V_CURRENT_FILE_ID,
            'sqlstate', V_ERROR_CODE,
            'error', V_ERROR_MESSAGE
        );
end;
$$;