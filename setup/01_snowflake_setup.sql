use role accountadmin;

create warehouse if not exists DBT_WH
  warehouse_size = 'XSMALL'
  auto_suspend = 60
  auto_resume = true
  initially_suspended = true;

create database if not exists DBT_MINI_PROJECT;
create role if not exists DBT_ROLE;

grant usage on warehouse DBT_WH to role DBT_ROLE;
grant usage on database DBT_MINI_PROJECT to role DBT_ROLE;
grant create schema on database DBT_MINI_PROJECT to role DBT_ROLE;

-- Demo only. In an organisation, create users through the approved identity process.
create user if not exists DBT_USER
  password = 'Replace_With_A_Strong_Password_123!'
  default_role = DBT_ROLE
  default_warehouse = DBT_WH
  must_change_password = true;

grant role DBT_ROLE to user DBT_USER;

