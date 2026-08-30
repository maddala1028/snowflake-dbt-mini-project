# Snowflake + dbt Mini Project

An interview-ready lending analytics project built from three datasets:

- `customers` — customer master data
- `applications` — loan/application lifecycle data
- `payments` — payments made against approved applications

The project demonstrates staging, dimensional modelling, incremental loading, an SCD Type 2 snapshot, reusable macros, generic tests, a singular business-rule test, source freshness, and dbt documentation.

## Architecture

```text
CSV seeds / Snowflake RAW tables
        |
        v
STAGING views: stg_customers, stg_applications, stg_payments
        |
        +--> snapshot_customers (SCD Type 2 history)
        |
        v
MARTS: dim_customers, fct_applications, fct_payments
        |
        v
application_payment_summary
```

## Prerequisites

- Snowflake account
- Python 3.9+
- dbt Core with the Snowflake adapter

## 1. Create Snowflake objects

Run `setup/01_snowflake_setup.sql` as a role allowed to create a database, warehouse, role, and user. Replace the sample password before running it.

## 2. Create the Python environment

```bash
python -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

## 3. Configure dbt

Copy `profiles.yml.example` to `~/.dbt/profiles.yml`, then set environment variables:

```bash
export SNOWFLAKE_ACCOUNT='your_account_identifier'
export SNOWFLAKE_USER='DBT_USER'
export SNOWFLAKE_PASSWORD='your_password'
```

Windows PowerShell:

```powershell
$env:SNOWFLAKE_ACCOUNT='your_account_identifier'
$env:SNOWFLAKE_USER='DBT_USER'
$env:SNOWFLAKE_PASSWORD='your_password'
```

Validate connectivity:

```bash
dbt debug
```

## 4. Run the project

```bash
dbt deps
dbt seed --full-refresh
dbt snapshot
dbt build
```

`dbt build` creates models and executes their tests in dependency order. To inspect lineage and descriptions:

```bash
dbt docs generate
dbt docs serve
```

## Expected schemas

| Schema | Objects | Purpose |
|---|---|---|
| `DBT_MINI_DEV` | three seed tables | Demo raw input |
| `DBT_MINI_DEV_STAGING` | three views | Clean names, types and values |
| `DBT_MINI_DEV_SNAPSHOTS` | customer snapshot | SCD Type 2 history |
| `DBT_MINI_DEV_MARTS` | dimensions, facts and summary | Analytics-ready layer |

## Models

| Model | Materialization | Grain |
|---|---|---|
| `stg_customers` | view | one row per customer |
| `stg_applications` | view | one row per application |
| `stg_payments` | view | one row per payment |
| `dim_customers` | table | one current row per customer |
| `fct_applications` | incremental | one row per application |
| `fct_payments` | incremental | one row per payment |
| `application_payment_summary` | table | one row per application |

## Incremental behaviour

The fact models use `updated_at` as a watermark and `merge` with a unique key. Re-running `dbt build` is idempotent. In production, include a small lookback window to safely handle late-arriving records.

## Suggested demonstration

1. Run the full project and show the DAG using dbt docs.
2. Change a customer's city or status in Snowflake.
3. Run `dbt snapshot` again and query the snapshot to show the old and current versions.
4. Add a new payment row, rerun `dbt build`, and explain the incremental merge.
5. Temporarily add an invalid payment amount and show the custom test failing.

## Production improvements

- Replace seeds with ingestion-managed RAW tables and define dbt sources with freshness metadata.
- Use separate DEV, TEST, and PROD targets and CI state comparison (`dbt build --select state:modified+`).
- Add orchestration through Airflow or dbt Cloud, alerting, query tags, role separation, and resource monitors.
- Add reconciliation checks between source counts/amounts and gold outputs.
- Store credentials in a secrets manager; never commit them.

