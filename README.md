# dbt-snowflake
Sample dbt models for telco database in snowflake sql

## What is dbt?
dbt (data build tool) is the "T" in ELT. You write transformations as plain `SELECT` statements in `.sql` files, and dbt compiles them into tables or views inside your warehouse (here, Snowflake).
Models reference each other with `{{ ref('model_name') }}`, which lets dbt build a dependency graph (DAG) and run models in the correct order.
It also runs tests (`not_null`, `unique`, etc.), generates documentation, and tracks source freshness.

## Medallion architecture mapping

The models are grouped into Bronze, Silver and Gold layers.

| Medallion layer | dbt layer | Folder | Purpose |
|---|---|---|---|
| Bronze | Sources (raw) | `RAW` schema, declared in `models/staging/sources.yml` | Data as landed by Snowpipe. dbt does not transform it. |
| Silver | Staging, Intermediate | `models/staging/`, `models/intermediate/` | Cleaned, typed, deduplicated and enriched data. |
| Gold | Marts, Reports | `models/marts/`, `models/reports/` | Business-ready facts, dimensions and aggregates for BI and ML. |

### Example: subscriber data flow

```
RAW.subscribers  ──►  stg_subscribers  ──►  dim_subscriber  ──►  rpt_arpu_by_plan
   (Bronze)             (Silver)              (Gold, mart)         (Gold, report)
```

- **Bronze:** `RAW.subscribers` is the raw table, declared with `{{ source('raw', 'subscribers') }}`.
- **Silver:** `stg_subscribers` selects from the source and cleans it. It masks the email, uppercases `status`, calculates `age`, and flattens the JSON `address` into `city`, `state`, `lat` and `lon`. It does no joins and no business logic.
- **Gold:** `dim_subscriber` joins `stg_subscribers` with `dim_plan` and `int_subscriber_plan_history` to add `plan_name`, `monthly_fee`, `tenure_months` and `plan_change_count`. `rpt_arpu_by_plan` then joins `fct_billing` and `dim_subscriber` to report revenue per user by plan.

## How staging and marts are related

- **Staging is the only entry point to raw data.** Each `stg_*` model maps one-to-one to a source table. It renames, casts and cleans columns, and nothing more.
- **Marts are built on staging.** They never read from `RAW` directly. They use `{{ ref('stg_...') }}` to read staging models, and often join them with other staging, intermediate or mart models.
- **Dependency direction:** `source → staging → (intermediate) → marts → reports`. Data flows in this direction only.
- **Why:** if the raw schema changes, you fix one staging model and every mart that depends on it keeps working. Cleaning logic stays in one place and business logic stays in the marts.

| Staging (Silver) | Used by (Gold) |
|---|---|
| `stg_subscribers` | `dim_subscriber` |
| `stg_plans` | `dim_plan` |
| `stg_cdr` | `int_cdr_enriched` → `fct_usage_daily` |
| `stg_invoices` | `int_invoice_lines` → `fct_billing` |
