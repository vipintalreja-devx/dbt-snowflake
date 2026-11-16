# Snowflake -> BigQuery Translation Report

Source: `../telco_dbt`. Target: `telco_dbt_bq`. Not compiled or run against BigQuery.

## Status legend
- DONE: direct translation
- REWRITE: no equivalent, logic rebuilt
- REDESIGN: needs a design decision
- DROPPED: not needed on BigQuery

| Object | Snowflake | BigQuery | Status | Risk |
|---|---|---|---|---|
| `stg_cdr` | `col:a.b::string`, `TRY_TO_TIMESTAMP_NTZ`, `ZEROIFNULL`, `REGEXP_SUBSTR` | `JSON_VALUE`, `SAFE.PARSE_DATETIME`, `IFNULL`, `REGEXP_EXTRACT` | DONE | Format codes differ (`YYYY` vs `%Y`); regex needs raw string |
| `stg_subscribers` | VARIANT path, `DATEDIFF(year,a,b)` | `JSON_VALUE`, `DATE_DIFF(b,a,year)` | DONE | Argument order flips |
| `stg_network_events` | `LATERAL FLATTEN(outer)` | `LEFT JOIN UNNEST(JSON_QUERY_ARRAY)` | DONE | Needs JSON column type in raw |
| `int_invoice_lines` | `TABLE(FLATTEN)` + `index` | `UNNEST ... WITH OFFSET` | DONE | None |
| `int_cdr_enriched` | `cluster_by`, `QUALIFY`, `md5_binary` | `partition_by` + `cluster_by`, `QUALIFY` with `WHERE true`, hex MD5 | DONE | Hash text differs from Snowflake binary; merge scans all partitions |
| `int_subscriber_plan_history` | `CONDITIONAL_CHANGE_EVENT` | Running `SUM(IF(change))` | REWRITE | Check the first row starts at 0 |
| `int_roaming_sessions` | `MATCH_RECOGNIZE` | Gaps-and-islands with `ROW_NUMBER` | REWRITE | Tie-breaks on equal timestamps use `cdr_id` |
| `dim_date` | `GENERATOR`, `DAYOFWEEKISO`, `MONTHNAME` | `GENERATE_DATE_ARRAY`, `FORMAT_DATE`, mod math | DONE | None |
| `dim_subscriber`, `dim_plan` | `9999-12-31::date` | `DATE '9999-12-31'` | DONE | None |
| `fct_usage_daily` | `delete+insert`, `snowflake_warehouse` | `insert_overwrite` on date partitions | REWRITE | Partitions list must cover lookback window |
| `fct_billing` | `merge`, `DATEDIFF`, `DIV0NULL` | `merge`, `DATE_DIFF`, `SAFE_DIVIDE` | DONE | `merge_exclude_columns` needs a recent dbt-bigquery |
| `fct_network_quality` | `MEDIAN`, `APPROX_PERCENTILE`, `MAX_BY` | `APPROX_QUANTILES`, `ARRAY_AGG ... LIMIT 1` | DONE | p50 is now approximate |
| `fct_churn_features` | `LISTAGG`, `OBJECT_CONSTRUCT`, `ARRAY_AGG` objects, `RATIO_TO_REPORT` | `STRING_AGG`, `TO_JSON(STRUCT)`, `ARRAY_AGG(STRUCT)`, `SAFE_DIVIDE` over `SUM` | DONE | `ticket_detail` is an array of structs, not VARIANT |
| `churn_score` | Snowpark Python | SQL min-max scaling | REWRITE | Same math as the sklearn scaler; check edge cases |
| `dt_realtime_usage` | Dynamic table, 5 min lag | Plain view | REDESIGN | Costs compute on every query; materialized view not possible here |
| `vw_subscriber_secure` | Secure view + `IS_ROLE_IN_SESSION` | Authorized view, IAM | REDESIGN | Row-level role logic moved out of SQL |
| `rpt_arpu_by_plan` | `ROLLUP`, `GROUPING(a,b)` | `ROLLUP` in CTE, two `GROUPING` calls | DONE | `grouping_id` rebuilt by hand |
| `rpt_usage_by_type` | `IFF` pivot macro | `IF` pivot macro | DONE | None |
| `rpt_status_pivot` | `PIVOT ... AS p (cols)` | `PIVOT` + outer rename | DONE | Column names are the pivot values |
| `rpt_high_value_sample` | `SAMPLE`, `TOP`, `AT(OFFSET)`, `ILIKE` | `TABLESAMPLE`, `LIMIT`, `FOR SYSTEM_TIME AS OF`, `LOWER LIKE` | DONE | Time travel limited to 7 days; sample needs a base table |
| Snapshots | timestamp, check | Same | DONE | Snapshot time columns follow source type (DATETIME) |
| Seeds | `varchar`, `number` | `string`, `numeric` | DONE | None |
| Macros: cents, divide, mask, local time, spine, pivot | Snowflake functions | BigQuery functions | DONE | `to_local_ts` expects a DATETIME in UTC |
| Macro `hash_key` | `snowflake__` | `bigquery__` added | DONE | Hex vs binary |
| Hooks: `set_query_tag`, `grant_select` | `ALTER SESSION`, `GRANT` | `query-comment` job labels, `+grants` | DROPPED | Replaced by config |
| Run-ops: `clone_prod_to_dev` | `CREATE DATABASE CLONE` | Table-by-table `CLONE` | REWRITE | One statement per table |
| Run-ops: `create_streams` | `CREATE STREAM` | `enable_change_history` | REDESIGN | Different read model (`CHANGES()`) |
| Run-ops: `unload_to_stage` | `COPY INTO @stage` | `EXPORT DATA` to GCS | DONE | Needs a bucket, not a stage |
| Run-ops: `resume_warehouse` | `ALTER WAREHOUSE` | None | DROPPED | No warehouse |
| Run-ops: `purge_old_dev_schemas` | `INFORMATION_SCHEMA`, `ILIKE ESCAPE` | Region `INFORMATION_SCHEMA.SCHEMATA` | DONE | Needs `target.location` |
| Generic tests | `DATEDIFF`, `REGEXP_LIKE` | `TIMESTAMP_DIFF`, `REGEXP_CONTAINS` | DONE | None |
| Non-dbt DDL (pipe, task, stream, policies, MV, UDF, share) | See `scripts/snowflake_setup.sql` | See `scripts/bigquery_setup.sql` | MIXED | Pipes, tasks, shares, masking need infra design |
| CI | `dbt-snowflake`, key pair | `dbt-bigquery`, workload identity | DONE | Set repo variables |

## Items to decide
1. `dt_realtime_usage`: view now. Use a scheduled table if cost matters.
2. Streams: pick `CHANGES()` or a watermark column per table.
3. Tasks and pipes: pick Composer, Workflows or dbt Cloud; Pub/Sub or transfer jobs.
4. Masking and row policies: build policy tags and data policies.
5. Hash keys: if keys are compared across systems, the values will not match.
