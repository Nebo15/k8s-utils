#!/bin/bash
K8S_UTILS_DIR="${BASH_SOURCE%/*}"
source ${K8S_UTILS_DIR}/helpers.sh

function show_help {
  echo "
  ktl pg:copy -istaging -utalkinto -dtalkinto [-q \"SELECT * FROM accounts;\" -nkube-system -h]

  Copies data from remote PostgreSQL database to a local one.

  Options:
    -iINSTANCE_NAME     Cloud SQL Instance name to which connection is established. Required.
    -uUSERNAME          PostgreSQL user name which would be used to log in. Required.
    -nNAMESPACE         Namespace for a pod that exposes PostgreSQL instance. Default: kube-system.
    -dpostgres          Database name. Required.
    -h                  Show help and exit.
    -t                  Name of a table that needs to be copied.
    -q                  Custom query which would be used to select copied data.
    -c                  Psql connection url for an instance to which the data is copied.


  Examples:
    ktl pg:copy -italkinto -utalkinto -dtalkinto -taccounts -c postgres://postgres:@localhost/talkinto_dev
    ktl pg:copy -italkinto -utalkinto -dtalkinto -taccounts -q \"SELECT * FROM accounts WHERE id = 1\" -c postgres://postgres:@localhost/talkinto_dev

  Available database instances:
"
  list_sql_proxy_users "ktl pg:copy -i\(.metadata.labels.instance_name) -u\(.data.username | @base64d) -d\$DATABASE_NAME" "  "
}

POSTGRES_USER=
INSTANCE_NAME=
PORT=$(get_free_random_port)
PROXY_POD_NAMESPACE="kube-system"
POSTGRES_CONNECTION_STRING=""
TABLE_NAME=""
COPY_QUERY=""

# Read configuration from CLI
while getopts "hn:i:u:d:t:q:c:" opt; do
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
    t)  TABLE_NAME="${OPTARG}"
        ;;
    q)  COPY_QUERY="${OPTARG}"
        ;;
    c)  DESTINATION_POSTGRES_CONNECTION_STRING="${OPTARG}"
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

if [[ "${TABLE_NAME}" == "" ]]; then
  error "Table name is not set, use -t option."
fi

if [[ "${COPY_QUERY}" == "" ]]; then
  COPY_QUERY="SELECT * FROM ${TABLE_NAME}"
fi

if [[ "${DESTINATION_POSTGRES_CONNECTION_STRING}" == "" ]]; then
  error "Destination connection URL is not set, use -c option."
fi

COPY_PATH="./ktl_pg_copy_tmp"
COPY_TMP_FILE_PATH="${COPY_PATH}/${TABLE_NAME}.csv"

if [[ -e "${COPY_PATH}" ]]; then
  error "${COPY_PATH} already exists, delete it with rm -rf ${COPY_PATH}"
fi

log_step "Selecting Cloud SQL proxy pod"
PROXY_POD_NAME=$(fetch_pod_name "${PROXY_POD_NAMESPACE}" "instance_name=${INSTANCE_NAME}")

POSTGRES_PASSWORD=$(get_postgres_user_password "${INSTANCE_NAME}" "${POSTGRES_USER}")
POSTGRES_CONNECTION_STRING=$(get_postgres_connection_url "${POSTGRES_USER}" "${POSTGRES_PASSWORD}" ${PORT} "${POSTGRES_DB}")

tunnel_postgres_connections "${PROXY_POD_NAMESPACE}" "${PROXY_POD_NAME}" ${PORT}

log_step "Temporary files will be stored in ${COPY_PATH}"
mkdir -p "${COPY_PATH}/"

log_step "Copying data using query '${COPY_QUERY}'"
set -x

psql "${POSTGRES_CONNECTION_STRING}" --echo-queries --command "\copy (${COPY_QUERY}) TO ${COPY_TMP_FILE_PATH} CSV HEADER;"

psql "${DESTINATION_POSTGRES_CONNECTION_STRING}" --echo-queries --command "\copy ${TABLE_NAME} FROM ${COPY_TMP_FILE_PATH} WITH CSV HEADER;"

set +x

log_step "Removing temporary files from ${COPY_PATH}"
rm -rf ${COPY_PATH}
