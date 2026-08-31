create or replace procedure DBT_MINI_PROJECT.PROCEDURES.SP_VALIDATE_WORK_BATCH(
    P_BATCH_ID varchar
)
returns variant
language sql
execute as owner
as
$$
declare
    V_BATCH_EXISTS       number default 0;
    V_ENTITY_NAME        varchar;
    V_TOTAL_ROWS         number default 0;
    V_VALID_ROWS         number default 0;
    V_INVALID_ROWS       number default 0;
    V_REJECTS_INSERTED   number default 0;
    V_ERROR_CODE         varchar;
    V_ERROR_MESSAGE      varchar;
begin

    /*--------------------------------------------------------------
      1. Validate input and locate the staged batch
    --------------------------------------------------------------*/
    if (P_BATCH_ID is null or trim(P_BATCH_ID) = '') then
        return object_construct(
            'status', 'FAILED',
            'error_code', 'INVALID_BATCH_ID',
            'error', 'P_BATCH_ID must not be null or empty'
        );
    end if;

    select
        count(*),
        max(entity_name)
    into
        :V_BATCH_EXISTS,
        :V_ENTITY_NAME
    from DBT_MINI_PROJECT.CONTROL.INGESTION_WORK
    where batch_id = :P_BATCH_ID;

    if (V_BATCH_EXISTS = 0) then
        return object_construct(
            'status', 'FAILED',
            'batch_id', P_BATCH_ID,
            'error_code', 'BATCH_NOT_FOUND',
            'error', 'No staged records were found for the supplied batch'
        );
    end if;

    /*--------------------------------------------------------------
      2. Mark batch records as being validated

      This also makes rerunning validation deterministic.
    --------------------------------------------------------------*/
    update DBT_MINI_PROJECT.CONTROL.INGESTION_WORK
       set validation_status = 'VALIDATING',
           validation_errors = array_construct()
     where batch_id = :P_BATCH_ID
       and processed_status = 'PENDING';

    /*--------------------------------------------------------------
      3. Create a session-scoped table containing validation errors
    --------------------------------------------------------------*/
    create or replace temporary table TMP_WORK_VALIDATION_ERRORS (
        WORK_RECORD_ID number,
        FIELD_NAME     varchar,
        ERROR_CODE     varchar,
        ERROR_MESSAGE  varchar
    );

    /*--------------------------------------------------------------
      4. Required-field validation

      REQUIRED_FIELDS is read dynamically from DATA_CONTRACT.
    --------------------------------------------------------------*/
    insert into TMP_WORK_VALIDATION_ERRORS (
        work_record_id,
        field_name,
        error_code,
        error_message
    )
    select
        W.work_record_id,
        F.value::varchar,
        'REQUIRED_FIELD_MISSING',
        'Required field ' || F.value::varchar ||
            ' is null, missing or empty'
    from DBT_MINI_PROJECT.CONTROL.INGESTION_WORK W
    join DBT_MINI_PROJECT.CONTROL.DATA_CONTRACT C
      on C.contract_id = W.contract_id
     and C.contract_version = W.contract_version,
    lateral flatten(input => C.required_fields) F
    where W.batch_id = :P_BATCH_ID
      and W.processed_status = 'PENDING'
      and nullif(
              trim(
                  get_path(
                      W.raw_record,
                      F.value::varchar
                  )::varchar
              ),
              ''
          ) is null;

    /*--------------------------------------------------------------
  5. ACCEPTED_VALUES validation
--------------------------------------------------------------*/
insert into TMP_WORK_VALIDATION_ERRORS (
    work_record_id,
    field_name,
    error_code,
    error_message
)
select
    W.work_record_id,
    R.key::varchar,
    'INVALID_ACCEPTED_VALUE',
    'Field ' || R.key::varchar ||
        ' contains unsupported value: ' ||
        coalesce(
            get_path(W.raw_record, R.key::varchar)::varchar,
            '<NULL>'
        )
from DBT_MINI_PROJECT.CONTROL.INGESTION_WORK W
join DBT_MINI_PROJECT.CONTROL.DATA_CONTRACT C
  on C.contract_id = W.contract_id
 and C.contract_version = W.contract_version,
lateral flatten(input => C.validation_rules) R,
lateral flatten(input => R.value:values) V
where W.batch_id = :P_BATCH_ID
  and W.processed_status = 'PENDING'
  and upper(R.value:rule_type::varchar) = 'ACCEPTED_VALUES'
  and get_path(W.raw_record, R.key::varchar) is not null
group by
    W.work_record_id,
    R.key::varchar,
    get_path(W.raw_record, R.key::varchar)::varchar
having count_if(
    upper(trim(V.value::varchar)) =
    upper(
        trim(
            get_path(
                W.raw_record,
                R.key::varchar
            )::varchar
        )
    )
) = 0;
    /*--------------------------------------------------------------
      6. GREATER_THAN validation
    --------------------------------------------------------------*/
    insert into TMP_WORK_VALIDATION_ERRORS (
        work_record_id,
        field_name,
        error_code,
        error_message
    )
    select
        W.work_record_id,
        R.key::varchar,
        'VALUE_NOT_GREATER_THAN',
        'Field ' || R.key::varchar ||
            ' must be greater than ' ||
            R.value:value::varchar
    from DBT_MINI_PROJECT.CONTROL.INGESTION_WORK W
    join DBT_MINI_PROJECT.CONTROL.DATA_CONTRACT C
      on C.contract_id = W.contract_id
     and C.contract_version = W.contract_version,
    lateral flatten(input => C.validation_rules) R
    where W.batch_id = :P_BATCH_ID
      and W.processed_status = 'PENDING'
      and upper(R.value:rule_type::varchar) = 'GREATER_THAN'
      and get_path(W.raw_record, R.key::varchar) is not null
      and (
          try_to_decimal(
              get_path(
                  W.raw_record,
                  R.key::varchar
              )::varchar,
              38,
              10
          ) is null
          or
          try_to_decimal(
              get_path(
                  W.raw_record,
                  R.key::varchar
              )::varchar,
              38,
              10
          ) <= try_to_decimal(
                   R.value:value::varchar,
                   38,
                   10
               )
      );

    /*--------------------------------------------------------------
      7. PATTERN or REGEX validation
    --------------------------------------------------------------*/
    insert into TMP_WORK_VALIDATION_ERRORS (
        work_record_id,
        field_name,
        error_code,
        error_message
    )
    select
        W.work_record_id,
        R.key::varchar,
        'PATTERN_MISMATCH',
        'Field ' || R.key::varchar ||
            ' does not match the configured pattern'
    from DBT_MINI_PROJECT.CONTROL.INGESTION_WORK W
    join DBT_MINI_PROJECT.CONTROL.DATA_CONTRACT C
      on C.contract_id = W.contract_id
     and C.contract_version = W.contract_version,
    lateral flatten(input => C.validation_rules) R
    where W.batch_id = :P_BATCH_ID
      and W.processed_status = 'PENDING'
      and (
          upper(R.value:rule_type::varchar) in (
              'PATTERN',
              'REGEX',
              'REGEX_MATCH'
          )
          or R.value:pattern is not null
      )
      and get_path(W.raw_record, R.key::varchar) is not null
      and not regexp_like(
          get_path(
              W.raw_record,
              R.key::varchar
          )::varchar,
          R.value:pattern::varchar
      );

    /*--------------------------------------------------------------
      8. Mark records containing validation errors as INVALID
    --------------------------------------------------------------*/
    update DBT_MINI_PROJECT.CONTROL.INGESTION_WORK W
       set validation_status = 'INVALID',
           validation_errors = E.validation_errors
      from (
          select
              work_record_id,
              array_agg(
                  object_construct(
                      'field', field_name,
                      'code', error_code,
                      'message', error_message
                  )
              ) within group (
                  order by field_name, error_code
              ) as validation_errors
          from TMP_WORK_VALIDATION_ERRORS
          group by work_record_id
      ) E
     where W.work_record_id = E.work_record_id
       and W.batch_id = :P_BATCH_ID;

    /*--------------------------------------------------------------
      9. Any record without errors is VALID
    --------------------------------------------------------------*/
    update DBT_MINI_PROJECT.CONTROL.INGESTION_WORK W
       set validation_status = 'VALID',
           validation_errors = array_construct()
     where W.batch_id = :P_BATCH_ID
       and W.processed_status = 'PENDING'
       and W.validation_status = 'VALIDATING'
       and not exists (
           select 1
           from TMP_WORK_VALIDATION_ERRORS E
           where E.work_record_id = W.work_record_id
       );

    /*--------------------------------------------------------------
  10. Prepare reject details without correlated subqueries
--------------------------------------------------------------*/
create or replace temporary table TMP_WORK_REJECT_DETAILS as
select
    W.work_record_id,
    array_agg(distinct E.value:field::varchar) as failed_fields
from DBT_MINI_PROJECT.CONTROL.INGESTION_WORK W,
lateral flatten(input => W.validation_errors) E
where W.batch_id = :P_BATCH_ID
  and W.validation_status = 'INVALID'
group by W.work_record_id;

/*--------------------------------------------------------------
  Insert invalid rows idempotently into the reject table
--------------------------------------------------------------*/
insert into DBT_MINI_PROJECT.REJECT.INGESTION_REJECT (
    batch_id,
    file_load_id,
    entity_name,
    contract_id,
    contract_version,
    full_file_path,
    file_name,
    file_row_number,
    ingestion_record_id,
    record_hash,
    raw_record,
    rejection_category,
    rejection_code,
    rejection_reason,
    failed_fields,
    validation_details,
    resolution_status,
    rejected_at,
    created_by
)
select
    W.batch_id,
    W.file_load_id,
    W.entity_name,
    W.contract_id,
    W.contract_version,
    W.source_object,
    W.file_name,
    W.file_row_number,
    W.ingestion_record_id,
    W.record_hash,
    W.raw_record,
    'CONTRACT_VALIDATION',
    'CONTRACT_VALIDATION_FAILED',
    'Record failed one or more data-contract rules',
    D.failed_fields,
    object_construct(
        'validation_errors', W.validation_errors
    ),
    'OPEN',
    current_timestamp(),
    current_user()
from DBT_MINI_PROJECT.CONTROL.INGESTION_WORK W
join TMP_WORK_REJECT_DETAILS D
  on D.work_record_id = W.work_record_id
left join DBT_MINI_PROJECT.REJECT.INGESTION_REJECT R
  on R.batch_id = W.batch_id
 and R.ingestion_record_id = W.ingestion_record_id
 and R.rejection_category = 'CONTRACT_VALIDATION'
where W.batch_id = :P_BATCH_ID
  and W.validation_status = 'INVALID'
  and R.reject_id is null;

V_REJECTS_INSERTED := SQLROWCOUNT;

    /*--------------------------------------------------------------
      11. Calculate final validation totals
    --------------------------------------------------------------*/
    select
        count(*),
        count_if(validation_status = 'VALID'),
        count_if(validation_status = 'INVALID')
    into
        :V_TOTAL_ROWS,
        :V_VALID_ROWS,
        :V_INVALID_ROWS
    from DBT_MINI_PROJECT.CONTROL.INGESTION_WORK
    where batch_id = :P_BATCH_ID;

    return object_construct(
        'status', 'VALIDATED',
        'batch_id', P_BATCH_ID,
        'entity_name', V_ENTITY_NAME,
        'total_rows', V_TOTAL_ROWS,
        'valid_rows', V_VALID_ROWS,
        'invalid_rows', V_INVALID_ROWS,
        'rejects_inserted', V_REJECTS_INSERTED
    );

exception
    when other then
        V_ERROR_CODE := SQLSTATE;
        V_ERROR_MESSAGE := SQLERRM;

        update DBT_MINI_PROJECT.CONTROL.INGESTION_WORK
           set validation_status = 'VALIDATION_FAILED',
               validation_errors = array_construct(
                   object_construct(
                       'code', :V_ERROR_CODE,
                       'message', :V_ERROR_MESSAGE
                   )
               )
         where batch_id = :P_BATCH_ID
           and validation_status = 'VALIDATING';

        return object_construct(
            'status', 'FAILED',
            'batch_id', P_BATCH_ID,
            'entity_name', V_ENTITY_NAME,
            'error_code', V_ERROR_CODE,
            'error', V_ERROR_MESSAGE
        );
end;
$$;

