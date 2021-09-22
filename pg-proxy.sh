#!/bin/bash
K8S_UTILS_DIR="${BASH_SOURCE%/*}"
source ${K8S_UTILS_DIR}/helpers.sh

function show_help {
  echo "
  ktl pg:proxy -istaging -utalkinto [-h -p5432 -dpostgres -nkube-system]

  Proxy PostgresSQL port to localhost.

  Options:
    -iINSTANCE_NAME     Cloud SQL Instance name to which connection is established. Required.
    -uUSERNAME          PostgreSQL user name which would be used to log in. Required.
    -nNAMESPACE         Namespace for a pod that exposes PostgreSQL instance. Default: kube-system.
    -pPORT              Local port for forwarding. Default: random port.
    -dpostgres          Database name to use to build connection URL. Default: postgres.
    -h                  Show help and exit.

  Examples:
    ktl pg:proxy -istaging -utalkinto -dtalkinto
    ktl pg:proxy -istaging -utalkinto -p5433

  Available databases:
"

  list_sql_proxy_users "ktl pg:proxy -i\(.metadata.labels.instance_name) -u\(.data.username | @base64d)" "  "
}

PORT=""
POSTGRES_DB="postgres"
PROXY_POD_NAMESPACE="kube-system"

INSTANCE_NAME=${KTL_PG_DEFAULT_INSTANCE_NAME}
POSTGRES_USER=${KTL_PG_DEFAULT_USERNAME}
POSTGRES_DB=${KTL_PG_DEFAULT_DATABASE}

# Read configuration from CLI
while getopts "hn:i:u:p:d:" opt; do
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
  esac
done

if [[ "${INSTANCE_NAME}" == "" ]]; then
  error "Instance name is not set, use -i option to set it or -h for list of available values"
fi

if [[ "${POSTGRES_USER}" == "" ]]; then
  error "User name is not set, use -u option to set it or -h for list of available values"
fi

if [[ "${PORT}" == "" && $(is_port_free "5433") == "true" ]]; then
  PORT="5433"
elif [[ "${PORT}" == ""  ]]; then
  PORT=$(get_free_random_port)
else
  ensure_port_is_free ${PORT}
fi

log_step "Selecting Cloud SQL proxy pod"
PROXY_POD_NAME=$(fetch_pod_name "${PROXY_POD_NAMESPACE}" "instance_name=${INSTANCE_NAME}")

POSTGRES_PASSWORD=$(get_postgres_user_password "${INSTANCE_NAME}" "${POSTGRES_USER}")
POSTGRES_CONNECTION_STRING=$(get_postgres_connection_url "${POSTGRES_USER}" "${POSTGRES_PASSWORD}" ${PORT} "${POSTGRES_DB}")

banner "You can use 'psql ${POSTGRES_CONNECTION_STRING}' command to connect to the database"

kubectl --namespace="${PROXY_POD_NAMESPACE}" port-forward ${PROXY_POD_NAME} ${PORT}:5432
