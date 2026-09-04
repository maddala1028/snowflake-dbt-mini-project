create or replace procedure DBT_MINI_PROJECT.PROCEDURES.SP_LOAD_VALIDATED_BATCH(
    P_BATCH_ID varchar
)
returns variant
language sql
execute as owner
as
$$
declare
    V_ENTITY_NAME          varchar;
    V_RAW_TARGET_TABLE     varchar;
    V_SQL                  varchar;

    V_BATCH_ROWS           number default 0;
    V_SOURCE_ROWS          number default 0;
    V_VALID_ROWS           number default 0;
    V_INVALID_ROWS         number default 0;
    V_LOADED_ROWS          number default 0;
    V_DUPLICATE_ROWS       number default 0;
    V_ACCOUNTED_ROWS       number default 0;
    V_VARIANCE_ROWS        number default 0;

    V_RECON_STATUS         varchar;
    V_ERROR_CODE           varchar;
    V_ERROR_MESSAGE        varchar;
begin

    /*------------------------------------------------------------
      1. Validate parameter
    ------------------------------------------------------------*/
    if (P_BATCH_ID is null or trim(P_BATCH_ID) = '') then
        return object_construct(
            'status', 'FAILED',
            'error_code', 'INVALID_BATCH_ID',
            'error', 'P_BATCH_ID must not be null or empty'
        );
    end if;

    /*------------------------------------------------------------
      2. Find batch, entity and contract RAW target
    ------------------------------------------------------------*/
    select
        count(*),
        max(W.entity_name),
        max(C.raw_target_table)
    into
        :V_BATCH_ROWS,
        :V_ENTITY_NAME,
        :V_RAW_TARGET_TABLE
    from DBT_MINI_PROJECT.CONTROL.INGESTION_WORK W
    join DBT_MINI_PROJECT.CONTROL.DATA_CONTRACT C
      on C.contract_id = W.contract_id
     and C.contract_version = W.contract_version
    where W.batch_id = :P_BATCH_ID;

    if (V_BATCH_ROWS = 0) then
        return object_construct(
            'status', 'FAILED',
            'batch_id', P_BATCH_ID,
            'error_code', 'BATCH_NOT_FOUND',
            'error', 'No work records were found for this batch'
        );
    end if;

    if (V_RAW_TARGET_TABLE is null) then
        return object_construct(
            'status', 'FAILED',
            'batch_id', P_BATCH_ID,
            'entity_name', V_ENTITY_NAME,
            'error_code', 'RAW_TARGET_NOT_CONFIGURED',
            'error', 'RAW_TARGET_TABLE is not configured in DATA_CONTRACT'
        );
    end if;

    /*
      Protect dynamic SQL by allowing only a fully qualified
      database.schema.table identifier.
    */
    if (
        not regexp_like(
            V_RAW_TARGET_TABLE,
            '^[A-Za-z0-9_$]+[.][A-Za-z0-9_$]+[.][A-Za-z0-9_$]+$'
        )
    ) then
        return object_construct(
            'status', 'FAILED',
            'batch_id', P_BATCH_ID,
            'entity_name', V_ENTITY_NAME,
            'error_code', 'INVALID_RAW_TARGET',
            'error', 'RAW_TARGET_TABLE is not a valid fully qualified name'
        );
    end if;

    /*------------------------------------------------------------
      3. Require every work record to have completed validation
    ------------------------------------------------------------*/
    select
        count(*),
        count_if(validation_status = 'VALID'),
        count_if(validation_status = 'INVALID')
    into
        :V_SOURCE_ROWS,
        :V_VALID_ROWS,
        :V_INVALID_ROWS
    from DBT_MINI_PROJECT.CONTROL.INGESTION_WORK
    where batch_id = :P_BATCH_ID;

    if (V_SOURCE_ROWS <> V_VALID_ROWS + V_INVALID_ROWS) then
        return object_construct(
            'status', 'FAILED',
            'batch_id', P_BATCH_ID,
            'entity_name', V_ENTITY_NAME,
            'error_code', 'BATCH_NOT_VALIDATED',
            'error',
                'Every work record must be VALID or INVALID before loading'
        );
    end if;

    /*------------------------------------------------------------
      4. Start RAW loading
    ------------------------------------------------------------*/
    update DBT_MINI_PROJECT.AUDIT.INGESTION_BATCH_AUDIT
       set batch_status = 'LOADING',
           source_row_count = :V_SOURCE_ROWS,
           rejected_row_count = :V_INVALID_ROWS,
           error_code = null,
           error_message = null,
           updated_at = current_timestamp()
     where batch_id = :P_BATCH_ID;

    update DBT_MINI_PROJECT.AUDIT.FILE_LOAD_AUDIT
       set file_status = 'LOADING',
           load_start_timestamp =
               coalesce(load_start_timestamp, current_timestamp()),
           error_code = null,
           error_message = null,
           updated_at = current_timestamp()
     where batch_id = :P_BATCH_ID;

    /*------------------------------------------------------------
      5. Identify records already present in RAW

      Dynamic UPDATE...FROM avoids unsupported correlated subqueries.
    ------------------------------------------------------------*/
    V_SQL :=
        'update DBT_MINI_PROJECT.CONTROL.INGESTION_WORK W ' ||
        'set processed_status = ''DUPLICATE'' ' ||
        'from ' || V_RAW_TARGET_TABLE || ' R ' ||
        'where W.batch_id = ? ' ||
        'and W.validation_status = ''VALID'' ' ||
        'and W.processed_status = ''PENDING'' ' ||
        'and R.record_hash = W.record_hash';

    execute immediate :V_SQL using (P_BATCH_ID);

    /*------------------------------------------------------------
      6. Insert only genuinely new validated records
    ------------------------------------------------------------*/
    V_SQL :=
        'insert into ' || V_RAW_TARGET_TABLE || ' (' ||
        '    ingestion_record_id,' ||
        '    entity_name,' ||
        '    raw_record,' ||
        '    record_hash,' ||
        '    source_system,' ||
        '    source_object,' ||
        '    file_type,' ||
        '    file_name,' ||
        '    file_row_number,' ||
        '    file_content_key,' ||
        '    file_last_modified,' ||
        '    scan_start_time,' ||
        '    load_timestamp,' ||
        '    batch_id,' ||
        '    run_mode,' ||
        '    contract_version,' ||
        '    source_date,' ||
        '    backfill_from_date,' ||
        '    backfill_to_date' ||
        ') ' ||
        'select ' ||
        '    W.ingestion_record_id,' ||
        '    W.entity_name,' ||
        '    W.raw_record,' ||
        '    W.record_hash,' ||
        '    W.source_system,' ||
        '    W.source_object,' ||
        '    W.file_type,' ||
        '    W.file_name,' ||
        '    W.file_row_number,' ||
        '    W.file_content_key,' ||
        '    W.file_last_modified,' ||
        '    W.scan_start_time,' ||
        '    current_timestamp(),' ||
        '    W.batch_id,' ||
        '    W.run_mode,' ||
        '    W.contract_version,' ||
        '    W.source_date,' ||
        '    W.backfill_from_date,' ||
        '    W.backfill_to_date ' ||
        'from DBT_MINI_PROJECT.CONTROL.INGESTION_WORK W ' ||
        'left join ' || V_RAW_TARGET_TABLE || ' R ' ||
        '  on R.record_hash = W.record_hash ' ||
        'where W.batch_id = ? ' ||
        'and W.validation_status = ''VALID'' ' ||
        'and W.processed_status = ''PENDING'' ' ||
        'and R.record_hash is null';

    execute immediate :V_SQL using (P_BATCH_ID);

    /*
      The INSERT completed successfully, so remaining PENDING valid
      records are the records inserted by this execution.
    */
    update DBT_MINI_PROJECT.CONTROL.INGESTION_WORK
       set processed_status = 'LOADED'
     where batch_id = :P_BATCH_ID
       and validation_status = 'VALID'
       and processed_status = 'PENDING';

    /*------------------------------------------------------------
      7. Calculate final counts from work status
    ------------------------------------------------------------*/
    select
        count_if(
            validation_status = 'VALID'
            and processed_status = 'LOADED'
        ),
        count_if(
            validation_status = 'VALID'
            and processed_status = 'DUPLICATE'
        )
    into
        :V_LOADED_ROWS,
        :V_DUPLICATE_ROWS
    from DBT_MINI_PROJECT.CONTROL.INGESTION_WORK
    where batch_id = :P_BATCH_ID;

    V_ACCOUNTED_ROWS :=
        V_LOADED_ROWS + V_INVALID_ROWS + V_DUPLICATE_ROWS;

    V_VARIANCE_ROWS :=
        V_SOURCE_ROWS - V_ACCOUNTED_ROWS;

    if (V_VARIANCE_ROWS = 0) then
        V_RECON_STATUS := 'PASSED';
    else
        V_RECON_STATUS := 'FAILED';
    end if;

    /*------------------------------------------------------------
      8. Calculate file-level results
    ------------------------------------------------------------*/
    create or replace temporary table TMP_FILE_LOAD_COUNTS as
    select
        file_load_id,
        count(*) as source_row_count,
        count_if(
            validation_status = 'VALID'
            and processed_status = 'LOADED'
        ) as loaded_row_count,
        count_if(
            validation_status = 'INVALID'
        ) as rejected_row_count,
        count_if(
            validation_status = 'VALID'
            and processed_status = 'DUPLICATE'
        ) as duplicate_row_count
    from DBT_MINI_PROJECT.CONTROL.INGESTION_WORK
    where batch_id = :P_BATCH_ID
    group by file_load_id;

    update DBT_MINI_PROJECT.AUDIT.FILE_LOAD_AUDIT F
       set source_row_count = C.source_row_count,
           loaded_row_count = C.loaded_row_count,
           rejected_row_count = C.rejected_row_count,
           duplicate_row_count = C.duplicate_row_count,

           file_status =
               case
                   when C.loaded_row_count > 0
                       then 'LOADED'
                   when C.duplicate_row_count = C.source_row_count
                       then 'SKIPPED'
                   when C.rejected_row_count = C.source_row_count
                       then 'REJECTED'
                   else 'COMPLETED'
               end,

           skip_reason =
               case
                   when C.duplicate_row_count = C.source_row_count
                       then 'All records already exist in RAW'
                   else null
               end,

           load_end_timestamp = current_timestamp(),
           updated_at = current_timestamp()
      from TMP_FILE_LOAD_COUNTS C
     where F.file_load_id = C.file_load_id
       and F.batch_id = :P_BATCH_ID;

    /*------------------------------------------------------------
      9. Update batch audit
    ------------------------------------------------------------*/
    update DBT_MINI_PROJECT.AUDIT.INGESTION_BATCH_AUDIT
       set batch_status =
               case
                   when :V_RECON_STATUS = 'PASSED'
                       then 'COMPLETED'
                   else 'RECONCILIATION_FAILED'
               end,

           end_timestamp = current_timestamp(),

           files_loaded =
               case
                   when :V_LOADED_ROWS > 0 then 1
                   else 0
               end,

           files_skipped =
               case
                   when :V_DUPLICATE_ROWS = :V_SOURCE_ROWS then 1
                   else 0
               end,

           files_failed =
               case
                   when :V_RECON_STATUS = 'FAILED' then 1
                   else 0
               end,

           source_row_count = :V_SOURCE_ROWS,
           loaded_row_count = :V_LOADED_ROWS,
           rejected_row_count = :V_INVALID_ROWS,
           duplicate_row_count = :V_DUPLICATE_ROWS,
           reconciliation_status = :V_RECON_STATUS,
           updated_at = current_timestamp()
     where batch_id = :P_BATCH_ID;

    /*------------------------------------------------------------
      10. Store or update reconciliation result idempotently
    ------------------------------------------------------------*/
    merge into DBT_MINI_PROJECT.AUDIT.RECONCILIATION_RESULT T
    using (
        select
            :P_BATCH_ID as batch_id,
            max(file_load_id) as file_load_id,
            :V_ENTITY_NAME as entity_name,
            :V_SOURCE_ROWS as source_row_count,
            :V_LOADED_ROWS as loaded_row_count,
            :V_INVALID_ROWS as rejected_row_count,
            :V_DUPLICATE_ROWS as duplicate_row_count,
            :V_ACCOUNTED_ROWS as accounted_row_count,
            :V_VARIANCE_ROWS as variance_count,
            :V_RECON_STATUS as reconciliation_status
        from DBT_MINI_PROJECT.CONTROL.INGESTION_WORK
        where batch_id = :P_BATCH_ID
    ) S
       on T.batch_id = S.batch_id
      and T.reconciliation_level = 'BATCH'
      and T.reconciliation_rule = 'SOURCE_EQUALS_ACCOUNTED'
    when matched then update set
        T.file_load_id = S.file_load_id,
        T.entity_name = S.entity_name,
        T.source_row_count = S.source_row_count,
        T.loaded_row_count = S.loaded_row_count,
        T.rejected_row_count = S.rejected_row_count,
        T.duplicate_row_count = S.duplicate_row_count,
        T.accounted_row_count = S.accounted_row_count,
        T.variance_count = S.variance_count,
        T.tolerance_count = 0,
        T.reconciliation_status = S.reconciliation_status,
        T.result_details = object_construct(
            'formula',
            'source = loaded + rejected + duplicate',
            'raw_target_table',
            :V_RAW_TARGET_TABLE
        ),
        T.checked_at = current_timestamp(),
        T.checked_by = current_user()
    when not matched then insert (
        batch_id,
        file_load_id,
        entity_name,
        reconciliation_level,
        reconciliation_rule,
        source_row_count,
        loaded_row_count,
        rejected_row_count,
        duplicate_row_count,
        accounted_row_count,
        variance_count,
        tolerance_count,
        reconciliation_status,
        result_details,
        checked_at,
        checked_by
    )
    values (
        S.batch_id,
        S.file_load_id,
        S.entity_name,
        'BATCH',
        'SOURCE_EQUALS_ACCOUNTED',
        S.source_row_count,
        S.loaded_row_count,
        S.rejected_row_count,
        S.duplicate_row_count,
        S.accounted_row_count,
        S.variance_count,
        0,
        S.reconciliation_status,
        object_construct(
            'formula',
            'source = loaded + rejected + duplicate',
            'raw_target_table',
            :V_RAW_TARGET_TABLE
        ),
        current_timestamp(),
        current_user()
    );

    return object_construct(
        'status',
            case
                when V_RECON_STATUS = 'PASSED'
                    then 'COMPLETED'
                else 'RECONCILIATION_FAILED'
            end,
        'batch_id', P_BATCH_ID,
        'entity_name', V_ENTITY_NAME,
        'raw_target_table', V_RAW_TARGET_TABLE,
        'source_rows', V_SOURCE_ROWS,
        'loaded_rows', V_LOADED_ROWS,
        'rejected_rows', V_INVALID_ROWS,
        'duplicate_rows', V_DUPLICATE_ROWS,
        'accounted_rows', V_ACCOUNTED_ROWS,
        'variance_rows', V_VARIANCE_ROWS,
        'reconciliation_status', V_RECON_STATUS
    );

exception
    when other then
        V_ERROR_CODE := SQLSTATE;
        V_ERROR_MESSAGE := SQLERRM;

        update DBT_MINI_PROJECT.AUDIT.INGESTION_BATCH_AUDIT
           set batch_status = 'FAILED',
               end_timestamp = current_timestamp(),
               error_code = :V_ERROR_CODE,
               error_message = :V_ERROR_MESSAGE,
               updated_at = current_timestamp()
         where batch_id = :P_BATCH_ID;

        update DBT_MINI_PROJECT.AUDIT.FILE_LOAD_AUDIT
           set file_status = 'FAILED',
               load_end_timestamp = current_timestamp(),
               error_code = :V_ERROR_CODE,
               error_message = :V_ERROR_MESSAGE,
               updated_at = current_timestamp()
         where batch_id = :P_BATCH_ID
           and file_status = 'LOADING';

        return object_construct(
            'status', 'FAILED',
            'batch_id', P_BATCH_ID,
            'entity_name', V_ENTITY_NAME,
            'raw_target_table', V_RAW_TARGET_TABLE,
            'error_code', V_ERROR_CODE,
            'error', V_ERROR_MESSAGE
        );
end;
$$;