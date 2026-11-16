# Telco dbt Project: Object Catalog

For each object: what it does, and what is Snowflake-specific in it.
"None" means the code is portable as written.

## Project config

| Object | Description | Snowflake-specific |
|---|---|---|
| `dbt_project.yml` | Layers, tags, vars, hooks | `+transient`, `+copy_grants`, `+query_tag` (Snowflake configs); post-hook grant |
| `profiles.yml.example` | Dev and prod targets | `type: snowflake`, key-pair auth, role, warehouse, `client_session_keep_alive` |
| `packages.yml` | dbt_utils, dbt_expectations | None |
| `selectors.yml` | Named job selections | None (uses `config.materialized` method) |

## Sources and seeds

| Object | Description | Snowflake-specific |
|---|---|---|
| `raw.cdr` | Call detail records from Snowpipe (voice, sms, data) | `VARIANT` column `raw_payload`; loaded by Snowpipe |
| `raw.subscribers` | Subscriber master | `VARIANT` address; masking policy and row access policy on the table |
| `raw.plans` | Plan price list | None |
| `raw.invoices` | Monthly invoices | `VARIANT` array `lines` |
| `raw.payments` | Payments against invoices | None |
| `raw.network_events` | Tower events with metric lists | `VARIANT` JSON with nested array |
| `raw.tickets` | Support tickets | None |
| `seeds/tower_cells` | Cell tower lookup (city, region, tech) | `column_types` use Snowflake types (`varchar`, `number`) |

## Staging models (views)

| Model | Description | Snowflake-specific |
|---|---|---|
| `stg_cdr` | Clean CDR: parsed timestamp, null-safe numbers, payload fields | `col:path::type` VARIANT access, `TRY_TO_TIMESTAMP_NTZ` with format, `ZEROIFNULL`, `REGEXP_SUBSTR` with `'e'` group arg |
| `stg_subscribers` | Subscribers with hashed email, age, city and geo | VARIANT path access, `DATEDIFF(year, ...)` argument order |
| `stg_plans` | Plans with dollar price and open-ended end date | `::number(18,2)` cast via macro, `INITCAP` |
| `stg_invoices` | Invoices in dollars, lines kept as array | `div`-by-100 cast via macro, VARIANT passthrough |
| `stg_payments` | Payments in dollars | `::timestamp_ntz` cast |
| `stg_network_events` | One row per event metric | `LATERAL FLATTEN(... outer => true)` on VARIANT |
| `stg_tickets` | Tickets with hours open | `DATEDIFF(hour, ...)` |

## Intermediate models

| Model | Description | Snowflake-specific |
|---|---|---|
| `int_cdr_enriched` | Deduped CDR joined to tower info; incremental | `merge` strategy, `cluster_by`, `QUALIFY`, `IFF`, `on_schema_change`, `convert_timezone`, `md5_binary` |
| `int_invoice_lines` | One row per invoice line | `TABLE(FLATTEN())`, `index` column, VARIANT access |
| `int_subscriber_plan_history` | Plan changes per subscriber from snapshot | `CONDITIONAL_CHANGE_EVENT` |
| `int_roaming_sessions` | Runs of consecutive roaming data events | `MATCH_RECOGNIZE` (no BigQuery equivalent) |

## Marts

| Model | Description | Snowflake-specific |
|---|---|---|
| `dim_date` | Calendar from 2024, 10 years | `GENERATOR`, `SEQ4`, `DAYOFWEEKISO`, `MONTHNAME`, `LAST_DAY`, `TO_CHAR` |
| `dim_plan` | Plans with tier and current flag | None |
| `dim_subscriber` | One row per subscriber with plan and tenure | `cluster_by` |
| `fct_usage_daily` | Daily usage per number | `delete+insert` incremental, `cluster_by`, per-model `snowflake_warehouse`, `COUNT_IF`, `APPROX_COUNT_DISTINCT` |
| `fct_billing` | Invoices with paid, balance and aging | `merge` with `merge_exclude_columns`, `DIV0NULL` via macro, `DATEDIFF` |
| `fct_network_quality` | Hourly latency and loss per cell | `MEDIAN`, `APPROX_PERCENTILE`, `MAX_BY`, `ARRAY_AGG ... WITHIN GROUP` |
| `fct_churn_features` | Feature table for churn | `LISTAGG DISTINCT ... WITHIN GROUP`, `OBJECT_CONSTRUCT`, `ARRAY_AGG` of objects, `RATIO_TO_REPORT` |
| `churn_score` (Python) | Churn score from features | Snowpark model; `packages` config; `snowflake_warehouse` |
| `dt_realtime_usage` | Per-minute usage, last 24 hours | `dynamic_table` materialization, `target_lag`, `on_configuration_change` |
| `vw_subscriber_secure` | Subscriber view limited by role | `secure` view, `copy_grants`, `IS_ROLE_IN_SESSION`, `CURRENT_ROLE` |

## Reports

| Model | Description | Snowflake-specific |
|---|---|---|
| `rpt_arpu_by_plan` | Revenue per user by month and plan | `ROLLUP`, `GROUPING()` |
| `rpt_usage_by_type` | Monthly voice, sms, data totals | Jinja-built pivot with `IFF` |
| `rpt_status_pivot` | Subscribers by state and status | Native `PIVOT` with alias list |
| `rpt_high_value_sample` | Sample of big bills | `SAMPLE (10)`, `TOP n`, time travel `AT(OFFSET)`, `ILIKE` |

## Snapshots

| Snapshot | Description | Snowflake-specific |
|---|---|---|
| `snap_subscribers` | History of subscriber changes (timestamp strategy) | `invalidate_hard_deletes`; none in SQL |
| `snap_plans` | History of plan price changes (check strategy) | None |

## Macros

| Macro | Description | Snowflake-specific |
|---|---|---|
| `cents_to_dollars` | Cents to a decimal amount | `::number(18,n)` cast |
| `safe_divide` | Divide, return 0 on zero | `DIV0NULL` |
| `mask_pii` | Hash a column | `SHA2(..., 256)` returns hex text |
| `to_local_ts` | UTC to project time zone | `CONVERT_TIMEZONE` |
| `date_spine_sf` | List of dates | `GENERATOR`, `SEQ4` |
| `hash_key` | Row key from columns | `adapter.dispatch`; `snowflake__` version uses `MD5_BINARY`, `CONCAT_WS` |
| `pivot_sum` | Build pivot columns in Jinja | `IFF` |
| `set_query_tag` | Tag each session | `ALTER SESSION SET query_tag` |
| `grant_select` | Grant on the built table | Snowflake `GRANT ... TO ROLE` |
| `log_run_results` | Write run results to audit table | None in logic; writes to a Snowflake schema |
| `clone_prod_to_dev` | Copy prod to a dev database | `CREATE DATABASE ... CLONE` |
| `create_streams` | Create CDC streams on raw tables | `CREATE STREAM`, `append_only` |
| `unload_to_stage` | Export a table to files | `COPY INTO @stage`, Parquet |
| `resume_warehouse` | Wake a warehouse | `ALTER WAREHOUSE ... RESUME` |
| `purge_old_dev_schemas` | Drop stale dev schemas | `INFORMATION_SCHEMA.SCHEMATA`, `ILIKE ... ESCAPE`, `DROP SCHEMA ... CASCADE` |
| `generate_schema_name` | Prod uses upper-case custom schema names | Snowflake upper-case naming |
| Generic tests: `positive_value`, `fresh_within_hours`, `valid_msisdn` | Data checks | `DATEDIFF`, `REGEXP_LIKE` |

## Tests

| Test | Description | Snowflake-specific |
|---|---|---|
| `assert_billing_balance_consistent` | Balance equals total minus paid | None |
| `assert_no_future_cdr` | No CDR dated in the future | `DATEADD`, `CURRENT_TIMESTAMP()` |

## Jobs and CI

| Object | Description | Snowflake-specific |
|---|---|---|
| `jobs/jobs.yml` | Hourly, nightly, weekly, Python, docs, dev refresh | Calls the Snowflake run-operations above |
| `.github/workflows/ci.yml` | Slim CI with `--defer` | `dbt-snowflake` adapter, key-pair secrets |

## Non-dbt Snowflake objects (`scripts/snowflake_setup.sql`)

| Object | Description | Snowflake-specific |
|---|---|---|
| Warehouse `TRANSFORM_WH` | Compute for dbt | Whole object is Snowflake-only |
| Resource monitor `TELCO_RM` | Credit cap | Snowflake-only |
| Tag `pii_level` | Label sensitive columns | Object tagging |
| Masking policy `mask_email` | Hide email unless role allows | Column masking policy |
| Row access policy `rap_region` | Filter rows by role | Row access policy |
| Tables `RAW.*` | Landing tables | `CLUSTER BY (expr)`, `data_retention_time_in_days`, `VARIANT`, `AUTOINCREMENT` |
| File format, stage `stg_cdr` | JSON file settings, S3 landing zone | Stage with storage integration |
| Pipe `pipe_cdr` | Auto-load files into CDR | Snowpipe `auto_ingest` |
| External table `EXT_TOWER_LOG` | Query Parquet in place | External table with `auto_refresh` |
| Streams `strm_cdr`, `strm_subscribers` | Track table changes | Streams (CDC) |
| Task `task_load_cdr_hourly` | Hourly count from stream | Task, cron schedule with time zone, `SYSTEM$STREAM_HAS_DATA` |
| Task `task_refresh_marts` | Run dbt after first task | Task graph (`AFTER`), `EXECUTE DBT PROJECT` |
| UDF `normalize_msisdn` | Clean a phone number | SQL UDF |
| UDF `bytes_to_gb_js` | Bytes to GB | JavaScript UDF |
| UDF `risk_bucket` | Score to HIGH/MEDIUM/LOW | Python UDF |
| Procedure `sp_archive_cdr` | Delete old CDR | Snowflake Scripting |
| Materialized view `mv_cdr_daily` | Daily CDR counts | Snowflake materialized view |
| Share `TELCO_SHARE` | Share data outside the account | Secure data sharing |
| Grants on future tables | Auto-grant to analysts | `FUTURE` grants |
| Table `AUDIT.dbt_run_log` | Run history | None |

## Caveat

The SQL was written by hand and was not compiled against a Snowflake account. Run `dbt parse` and `dbt compile` before using it as a test corpus.
