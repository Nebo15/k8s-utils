#!/bin/bash
K8S_UTILS_DIR="${BASH_SOURCE%/*}"
source ${K8S_UTILS_DIR}/helpers.sh

function show_help {
  echo "
  ktl pg:kill -istaging -utalkinto -p3443 -dtalkinto [-nkube-system -h -f]

  Kill a query by pid.

  Options:
    -iINSTANCE_NAME     Cloud SQL Instance name to which connection is established. Required.
    -uUSERNAME          PostgreSQL user name which would be used to log in. Required.
    -nNAMESPACE         Namespace for a pod that exposes PostgreSQL instance. Default: kube-system.
    -dpostgres          Database name to use. Default: postgres.
    -pPID               Query PID.
    -f                  Force kill.
    -h                  Show help and exit.

  Examples:
    ktl pg:kill -istaging -utalkinto -dtalkinto -p3453

  Available databases:
"

  list_sql_proxy_users "ktl pg:kill -i\(.metadata.labels.instance_name) -u\(.data.username | @base64d) -d\$DATABASE_NAME -p\$PID" "  "
}

PORT=$(get_free_random_port)
POSTGRES_DB="postgres"
PROXY_POD_NAMESPACE="kube-system"
COMMAND="pg_cancel_backend"

# Read configuration from CLI
while getopts "hn:i:u:d:fp:" opt; do
  case "$opt" in
    n)  PROXY_POD_NAMESPACE="${OPTARG}"
        ;;
    i)  INSTANCE_NAME="${OPTARG}"
        ;;
    u)  POSTGRES_USER="${OPTARG}"
        ;;
    p)  PID="${OPTARG}"
        ;;
    d)  POSTGRES_DB="${OPTARG}"
        ;;
    h)  show_help
        exit 0
        ;;
    f)  COMMAND="pg_terminate_backend"
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

if [[ "${PID}" == "" ]]; then
  error "PID to kill is not set, use -p option."
fi

log_step "Selecting Cloud SQL proxy pod"
PROXY_POD_NAME=$(fetch_pod_name "${PROXY_POD_NAMESPACE}" "instance_name=${INSTANCE_NAME}")

POSTGRES_PASSWORD=$(get_postgres_user_password "${INSTANCE_NAME}" "${POSTGRES_USER}")
POSTGRES_CONNECTION_STRING=$(get_postgres_connection_url "${POSTGRES_USER}" "${POSTGRES_PASSWORD}" ${PORT} "${POSTGRES_DB}")

tunnel_postgres_connections "${PROXY_POD_NAMESPACE}" "${PROXY_POD_NAME}" ${PORT}

psql "${POSTGRES_CONNECTION_STRING}" --no-psqlrc --command "SELECT ${COMMAND}(${PID});"
