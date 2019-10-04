#!/bin/bash
K8S_UTILS_DIR="${BASH_SOURCE%/*}"
source ${K8S_UTILS_DIR}/helpers.sh

function show_help {
  echo "
  ktl pg:outliers -istaging -utalkinto -dtalkinto [-nkube-system -h -r -t -n]

  Show queries that have longest execution time in aggregate. Requires pg_stat_statements.

  If you get ERROR:  42P01: relation \"pg_stat_statements\" does not exist, then pg_stat_statements
  extension is not enabled. To enable it run execute \"CREATE EXTENSION pg_stat_statements\".

  Options:
    -iINSTANCE_NAME     Cloud SQL Instance name to which connection is established. Required.
    -uUSERNAME          PostgreSQL user name which would be used to log in. Required.
    -nNAMESPACE         Namespace for a pod that exposes PostgreSQL instance. Default: kube-system.
    -dpostgres          Database name to use. Required.
    -h                  Show help and exit.
    -t                  Do not truncate queries to 40 characters.
    -r                  Resets statistics gathered by pg_stat_statements.
    -c10                Number of queries to display. Default: 10.

  Examples:
    ktl pg:outliers -istaging -utalkinto -dtalkinto
    ktl pg:outliers -istaging -utalkinto -dtalkinto -r -c10 -t

  Available databases:
"

  list_sql_proxy_users "ktl pg:outliers -i\(.metadata.labels.instance_name) -u\(.data.username | @base64d) -d\$DATABASE_NAME" "  "
}

PORT=$(get_free_random_port)
POSTGRES_DB="postgres"
PROXY_POD_NAMESPACE="kube-system"
RESET=""
NUMBER=10
TRUNCATE="CASE WHEN length(query) <= 40 THEN query ELSE substr(query, 0, 39) || '…' END"

# Read configuration from CLI
while getopts "hn:i:u:p:rn:td:" opt; do
  case "$opt" in
    n)  PROXY_POD_NAMESPACE="${OPTARG}"
        ;;
    i)  INSTANCE_NAME="${OPTARG}"
        ;;
    u)  POSTGRES_USER="${OPTARG}"
        ;;
    p)  PORT="${OPTARG}"
        ;;
    d)  POSTGRES_DB="${OPTARG}"
        ;;
    h)  show_help
        exit 0
        ;;
    r)  RESET="true"
        ;;
    n)  NUMBER="${OPTARG}"
        ;;
    t)  TRUNCATE="query"
        ;;
  esac
done

if [[ "${INSTANCE_NAME}" == "" ]]; then
  error "Instance name is not set, use -i option to set it or -h for list of available values"
fi

if [[ "${POSTGRES_USER}" == "" ]]; then
  error "User name is not set, use -u option to set it or -h for list of available values"
fi

if [[ "${POSTGRES_DB}" == "" ]]; then
  error "Posgres database is not set, use -d option."
fi

log_step "Selecting Cloud SQL proxy pod"
PROXY_POD_NAME=$(fetch_pod_name "${PROXY_POD_NAMESPACE}" "instance_name=${INSTANCE_NAME}")

POSTGRES_PASSWORD=$(get_postgres_user_password "${INSTANCE_NAME}" "${POSTGRES_USER}")
POSTGRES_CONNECTION_STRING=$(get_postgres_connection_url "${POSTGRES_USER}" "${POSTGRES_PASSWORD}" ${PORT} "${POSTGRES_DB}")

tunnel_postgres_connections "${PROXY_POD_NAMESPACE}" "${PROXY_POD_NAME}" ${PORT}

if [[ "${RESET}" == "true" ]]; then
  psql "${POSTGRES_CONNECTION_STRING}" --no-psqlrc --command "SELECT pg_stat_statements_reset();"
fi

psql "${POSTGRES_CONNECTION_STRING}" --no-psqlrc --command "
  SELECT
    rolname AS rolname,
    interval '1 millisecond' * total_time AS total_exec_time,
    to_char((total_time/sum(total_time) OVER()) * 100, 'FM90D0') || '%' AS prop_exec_time,
    mean_time,
    max_time,
    stddev_time,
    interval '1 millisecond' * (blk_read_time + blk_write_time) AS sync_io_time,
    rows,
    to_char(calls, 'FM999G999G999G990') AS ncalls,
    regexp_replace(${TRUNCATE}, '[ \t\n]+', ' ', 'g') AS query
  FROM pg_stat_statements
  JOIN pg_roles r ON r.oid = userid
  WHERE userid = (SELECT usesysid FROM pg_user WHERE usename = current_user LIMIT 1)
  ORDER BY total_time DESC
  LIMIT ${NUMBER}
"
