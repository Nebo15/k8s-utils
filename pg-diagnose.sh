#!/bin/bash
K8S_UTILS_DIR="${BASH_SOURCE%/*}"
source ${K8S_UTILS_DIR}/helpers.sh

function show_help {
  echo "
  ktl pg:diagnose -istaging -utalkinto [-nkube-system -h]

  Shows diagnostics report for PostgreSQL database.

  Options:
    -iINSTANCE_NAME     Cloud SQL Instance name to which connection is established. Required.
    -uUSERNAME          PostgreSQL user name which would be used to log in. Required.
    -nNAMESPACE         Namespace for a pod that exposes PostgreSQL instance. Default: kube-system.
    -h                  Show help and exit.

  Examples:
    ktl pg:diagnose -istaging -utalkinto
    ktl pg:diagnose -istaging -utalkinto -nkube-system

  Available databases:
"

  list_sql_proxy_users "ktl pg:diagnose -i\(.metadata.labels.instance_name) -u\(.data.username | @base64d)" "  "
}

# TODO: add more stats from https://github.com/heroku/heroku-pg-extras

PORT=$(get_free_random_port)
POSTGRES_DB="postgres"
PROXY_POD_NAMESPACE="kube-system"

# Read configuration from CLI
while getopts "hn:i:u:" opt; do
  case "$opt" in
    n)  PROXY_POD_NAMESPACE="--namespace=${OPTARG}"
        ;;
    i)  INSTANCE_NAME="${OPTARG}"
        ;;
    u)  POSTGRES_USER="${OPTARG}"
        ;;
    h)  show_help
        exit 0
        ;;
  esac
done

if [[ "${INSTANCE_NAME}" == "" ]]; then
  error "Instance name is not set, use -i option to set it or -h for list of available values"
fi

if [[ "${POSTGRES_USER}" == "" ]]; then
  error "User name is not set, use -u option to set it or -h for list of available values"
fi

log_step "Selecting Cloud SQL proxy pod"
PROXY_POD_NAME=$(fetch_pod_name "${PROXY_POD_NAMESPACE}" "instance_name=${INSTANCE_NAME}")

POSTGRES_PASSWORD=$(get_postgres_user_password "${INSTANCE_NAME}" "${POSTGRES_USER}")
POSTGRES_CONNECTION_STRING=$(get_postgres_connection_url "${POSTGRES_USER}" "${POSTGRES_PASSWORD}" ${PORT} "${POSTGRES_DB}")

tunnel_postgres_connections "${PROXY_POD_NAMESPACE}" "${PROXY_POD_NAME}" ${PORT}

psql "${POSTGRES_CONNECTION_STRING}" --no-psqlrc --command "
  WITH table_scans as (
      SELECT relid,
          tables.idx_scan + tables.seq_scan as all_scans,
          ( tables.n_tup_ins + tables.n_tup_upd + tables.n_tup_del ) as writes,
                  pg_relation_size(relid) as table_size
          FROM pg_stat_user_tables as tables
  ),
  all_writes as (
      SELECT sum(writes) as total_writes
      FROM table_scans
  ),
  indexes as (
      SELECT idx_stat.relid, idx_stat.indexrelid,
          idx_stat.schemaname, idx_stat.relname as tablename,
          idx_stat.indexrelname as indexname,
          idx_stat.idx_scan,
          pg_relation_size(idx_stat.indexrelid) as index_bytes,
          indexdef ~* 'USING btree' AS idx_is_btree
      FROM pg_stat_user_indexes as idx_stat
          JOIN pg_index
              USING (indexrelid)
          JOIN pg_indexes as indexes
              ON idx_stat.schemaname = indexes.schemaname
                  AND idx_stat.relname = indexes.tablename
                  AND idx_stat.indexrelname = indexes.indexname
      WHERE pg_index.indisunique = FALSE
  ),
  index_ratios AS (
  SELECT schemaname, tablename, indexname,
      idx_scan, all_scans,
      round(( CASE WHEN all_scans = 0 THEN 0.0::NUMERIC
          ELSE idx_scan::NUMERIC/all_scans * 100 END),2) as index_scan_pct,
      writes,
      round((CASE WHEN writes = 0 THEN idx_scan::NUMERIC ELSE idx_scan::NUMERIC/writes END),2)
          as scans_per_write,
      pg_size_pretty(index_bytes) as index_size,
      pg_size_pretty(table_size) as table_size,
      idx_is_btree, index_bytes
      FROM indexes
      JOIN table_scans
      USING (relid)
  ),
  index_groups AS (
  SELECT 'Never Used Indexes' as reason, *, 1 as grp
  FROM index_ratios
  WHERE
      idx_scan = 0
      and idx_is_btree
  UNION ALL
  SELECT 'Low Scans, High Writes' as reason, *, 2 as grp
  FROM index_ratios
  WHERE
      scans_per_write <= 1
      and index_scan_pct < 10
      and idx_scan > 0
      and writes > 100
      and idx_is_btree
  UNION ALL
  SELECT 'Seldom Used Large Indexes' as reason, *, 3 as grp
  FROM index_ratios
  WHERE
      index_scan_pct < 5
      and scans_per_write > 1
      and idx_scan > 0
      and idx_is_btree
      and index_bytes > 100000000
  UNION ALL
  SELECT 'High-Write Large Non-Btree' as reason, index_ratios.*, 4 as grp
  FROM index_ratios, all_writes
  WHERE
      ( writes::NUMERIC / ( total_writes + 1 ) ) > 0.02
      AND NOT idx_is_btree
      AND index_bytes > 100000000
  ORDER BY grp, index_bytes DESC )
  SELECT reason, schemaname, tablename, indexname,
      index_scan_pct, scans_per_write, index_size, table_size
  FROM index_groups;
"
