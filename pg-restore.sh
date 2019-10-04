#!/bin/bash
K8S_UTILS_DIR="${BASH_SOURCE%/*}"
source ${K8S_UTILS_DIR}/helpers.sh

function show_help {
  echo "
  ktl pg:restore -istaging -utalkinto -dtalkinto [-nkube-system -h -eschema_migrations -tapis,plugins -f dumps/ -dpostgres]

  Restores PostgreSQL database from a local directory (in binary format).

  Options:
    -iINSTANCE_NAME     Cloud SQL Instance name to which connection is established. Required.
    -uUSERNAME          PostgreSQL user name which would be used to log in. Required.
    -nNAMESPACE         Namespace for a pod that exposes PostgreSQL instance. Default: kube-system.
    -dpostgres          Database name. Required.
    -t                  List of tables to export. By default all tables are exported. Comma delimited.
    -e                  List of tables to exclude from export. Comma delimited. By default no tables are ignored.
    -f                  Path to directory where dumps are stored. By default: ./dumps
    -h                  Show help and exit.
    -o                  Only insert data.

  Examples:
    ktl pg:restore -dtalkinto -istaging -utalkinto
    ktl pg:restore -dtalkinto -istaging -utalkinto -eschema_migrations
    ktl pg:restore -dtalkinto -istaging -utalkinto -tapis,plugins,requests

  Available databases:
"
  list_sql_proxy_users "ktl pg:restore -i\(.metadata.labels.instance_name) -u\(.data.username | @base64d) -d\$DATABASE_NAME" "  "
}

PORT=$(get_free_random_port)
PROXY_POD_NAMESPACE="kube-system"

DUMP_PATH="./dumps"
TABLES=""
EXCLUDE_TABLES=""
DATA_ONLY=""

# Read configuration from CLI
while getopts "hn:i:u:d:t:e:f:o" opt; do
  case "$opt" in
    n)  PROXY_POD_NAMESPACE="${OPTARG}"
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
    t)  TABLES="${OPTARG}"
        TABLES="--table=${TABLES//,/ --table=}"
        ;;
    f)  DUMP_PATH="${OPTARG}"
        ;;
    e)  EXCLUDE_TABLES="${OPTARG}"
        EXCLUDE_TABLES="--exclude-table=${EXCLUDE_TABLES//,/ --exclude-table=}"
        ;;
    o)  DATA_ONLY="--data-only"
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

if [[ ! -e "${DUMP_PATH}/${POSTGRES_DB}" ]]; then
  error "${DUMP_PATH}/${POSTGRES_DB} does not exist, specify backup path with -f option"
fi

log_step "Selecting Cloud SQL proxy pod"
PROXY_POD_NAME=$(fetch_pod_name "${PROXY_POD_NAMESPACE}" "instance_name=${INSTANCE_NAME}")

POSTGRES_PASSWORD=$(get_postgres_user_password "${INSTANCE_NAME}" "${POSTGRES_USER}")
POSTGRES_CONNECTION_STRING=$(get_postgres_connection_url "${POSTGRES_USER}" "${POSTGRES_PASSWORD}" ${PORT} "${POSTGRES_DB}")

tunnel_postgres_connections "${PROXY_POD_NAMESPACE}" "${PROXY_POD_NAME}" ${PORT}

log_step "Restoring remote ${POSTGRES_DB} DB from ./dumps/${POSTGRES_DB}"

set -x
PGPASSWORD="$POSTGRES_PASSWORD" \
pg_restore dumps/${POSTGRES_DB} \
  -h localhost \
  -p ${PORT} \
  -U ${POSTGRES_USER} \
  -d ${POSTGRES_DB} \
  --verbose \
  --no-acl \
  --no-owner \
  --format c ${TABLES} ${EXCLUDE_TABLES} ${DATA_ONLY}
set +x
