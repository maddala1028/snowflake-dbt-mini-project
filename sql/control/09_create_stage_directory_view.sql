create or replace view
DBT_MINI_PROJECT.CONTROL.V_STAGE_FILE_DIRECTORY
as
select
    'DBT_MINI_PROJECT.DBT_MINI_DEV.S3_DBT_MINI_STAGE'
        as stage_name,
    relative_path,
    regexp_substr(relative_path, '[^/]+$')
        as file_name,
    size as file_size_bytes,
    md5 as file_checksum,
    last_modified as file_last_modified
from directory(
    @DBT_MINI_PROJECT.DBT_MINI_DEV.S3_DBT_MINI_STAGE
);

select *
from DBT_MINI_PROJECT.CONTROL.V_STAGE_FILE_DIRECTORY
order by relative_path;