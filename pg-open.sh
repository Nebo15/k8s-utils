#!/bin/bash
K8S_UTILS_DIR="${BASH_SOURCE%/*}"
source ${K8S_UTILS_DIR}/helpers.sh

function show_help {
  echo "
  ktl pg:open -istaging -utalkinto [-h -p5432 -dpostgres -nkube-system]

  Run psql on localhost and connect it to a remote PostgreSQL instance.

  Options:
    -iINSTANCE_NAME     Cloud SQL Instance name to which connection is established. Required.
    -uUSERNAME          PostgreSQL user name which would be used to log in. Required.
    -nNAMESPACE         Namespace for a pod that exposes PostgreSQL instance. Default: kube-system.
    -pPORT              Local port for forwarding. Default: random port.
    -dpostgres          Database name to use. Default: postgres.
    -h                  Show help and exit.

  Examples:
    ktl pg:open -istaging -utalkinto -dtalkinto
    ktl pg:open -istaging -utalkinto -p5433

  Available databases:
"

  list_sql_proxy_users "ktl pg:open -i\(.metadata.labels.instance_name) -u\(.data.username | @base64d)" "  "
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

tunnel_postgres_connections "${PROXY_POD_NAMESPACE}" "${PROXY_POD_NAME}" ${PORT}

echo " - Running: open postgres://${POSTGRES_USER}:***@localhost:${PORT}/${POSTGRES_DB}?create_favorite=true&connect_favorite=true&nickname=ktl/${INSTANCE_NAME}/${POSTGRES_DB}/${POSTGRES_USER}"
open "${POSTGRES_CONNECTION_STRING}?create_favorite=true&connect_favorite=true&nickname=ktl/${INSTANCE_NAME}/${POSTGRES_DB}/${POSTGRES_USER}"
fg
