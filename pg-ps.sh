#!/bin/bash
K8S_UTILS_DIR="${BASH_SOURCE%/*}"
source ${K8S_UTILS_DIR}/helpers.sh

function show_help {
  echo "
  ktl pg:ps -istaging -utalkinto -dtalkinto [-nkube-system -h -v]

  View active queries with execution time.

  Options:
    -iINSTANCE_NAME     Cloud SQL Instance name to which connection is established. Required.
    -uUSERNAME          PostgreSQL user name which would be used to log in. Required.
    -nNAMESPACE         Namespace for a pod that exposes PostgreSQL instance. Default: kube-system.
    -dpostgres          Database name to use. Required.
    -h                  Show help and exit.
    -v                  Verbose output, includes idle transactions.

  Examples:
    ktl pg:ps -istaging -utalkinto -dtalkinto

  Available databases:
"

  list_sql_proxy_users "ktl pg:ps -i\(.metadata.labels.instance_name) -u\(.data.username | @base64d) -d\$DATABASE_NAME" "  "
}

PORT=$(get_free_random_port)
POSTGRES_DB="postgres"
PROXY_POD_NAMESPACE="kube-system"
VERBOSE="AND state <> 'idle'"

# Read configuration from CLI
while getopts "hn:i:u:d:v" opt; do
  case "$opt" in
    n)  PROXY_POD_NAMESPACE="--namespace=${OPTARG}"
        ;;
    i)  INSTANCE_NAME="${OPTARG}"
        ;;
    u)  POSTGRES_USER="${OPTARG}"
        ;;
    d)  POSTGRES_DB="${OPTARG}"
        ;;
    h)  show_help
        exit 0
        ;;
    v)  VERBOSE=""
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

WAIT_RAND=$(awk 'BEGIN{srand();print int(rand()*(63000-2000))+2000 }')
WAIT_RETURN=$(
  psql "${POSTGRES_CONNECTION_STRING}" --no-psqlrc --command "SELECT '${WAIT_RAND}' || '${WAIT_RAND}' WHERE EXISTS (
    SELECT 1 FROM information_schema.columns WHERE table_schema = 'pg_catalog'
      AND table_name = 'pg_stat_activity'
      AND column_name = 'waiting'
  )
  "
)

if [[ "${WAIT_RETURN}"  = *"${WAIT_RAND}${WAIT_RAND}"* ]]; then
  WAITING="waiting"
else
  WAITING="wait_event IS NOT NULL AS waiting"
fi

echo "Active queries: "
psql "${POSTGRES_CONNECTION_STRING}" --no-psqlrc --command "
  SELECT
    pid,
    state,
    application_name AS source,
    usename AS username,
    age(now(),xact_start) AS running_for,
    xact_start AS transaction_start,
    ${WAITING},
    query
  FROM pg_stat_activity
  WHERE query <> '<insufficient privilege>'
        ${VERBOSE}
        AND pid <> pg_backend_pid()
  ORDER BY query_start DESC
"

echo "Queries with active locks: "
psql "${POSTGRES_CONNECTION_STRING}" --no-psqlrc --command "
  SELECT
    pg_stat_activity.pid,
    pg_class.relname,
    pg_locks.transactionid,
    pg_locks.granted,
    CASE WHEN length(pg_stat_activity.query) <= 40 THEN pg_stat_activity.query ELSE substr(pg_stat_activity.query, 0, 39) || '…' END AS query_snippet,
    age(now(),pg_stat_activity.query_start) AS lock_age
  FROM pg_stat_activity,pg_locks left
  OUTER JOIN pg_class
    ON (pg_locks.relation = pg_class.oid)
  WHERE pg_stat_activity.query <> '<insufficient privilege>'
    AND pg_locks.pid = pg_stat_activity.pid
    AND pg_locks.mode = 'ExclusiveLock'
    AND pg_stat_activity.pid <> pg_backend_pid() order by query_start;
"
