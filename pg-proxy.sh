#!/bin/bash
set -em

function show_help {
  echo "
  ktl pg:proxy [-lapp=db -ndefault -h -p5432 -dpostgres]

  Proxy PostgresSQL port to localhost.

  Options:
    -lSELECTOR          Selector for a pod that exposes PostgreSQL instance. Default: app=db.
    -nNAMESPACE         Namespace for a pod that exposes PostgreSQL instance. Default: default.
    -pPORT              Local port for forwarding. Default: 5432.
    -dpostgres          Database name to use.
    -h                  Show help and exit.

  Examples:
    ktl pg:proxy
    ktl pg:proxy -p5433
    ktl pg:proxy -lapp=readonly-db
"
}

K8S_SELECTOR="app=db"
PORT="5432"
POSTGRES_DB="postgres"

# Read configuration from CLI
while getopts "hn:l:p:d:" opt; do
  case "$opt" in
    n)  K8S_NAMESPACE="--namespace=${OPTARG}"
        ;;
    l)  K8S_SELECTOR="${OPTARG}"
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

set +e
nc -z localhost ${PORT} < /dev/null
if [[ $? == "0" ]]; then
  echo "[E] Port ${PORT} is busy, try to specify different port name with -p option."
  exit 1
fi
set -e

echo " - Selecting pod with '-l ${K8S_SELECTOR} -n ${K8S_NAMESPACE:-default}' selector."
SELECTED_PODS=$(
  kubectl get pods ${K8S_NAMESPACE} \
    -l ${K8S_SELECTOR} \
    -o json \
    --field-selector=status.phase=Running
)
POD_NAME=$(echo ${SELECTED_PODS} | jq -r '.items[0].metadata.name')

if [ ! ${POD_NAME} ]; then
  echo "[E] Pod wasn't found. Try to select it with -n (namespace) and -l options."
  exit 1
fi

echo " - Found pod ${POD_NAME}."

DB_CONNECTION_SECRET=$(echo ${SELECTED_PODS} | jq -r '.items[0].metadata.labels.connectionSecret')
echo " - Resolving database user and password from secret ${DB_CONNECTION_SECRET}."
DB_SECRET=$(kubectl get secrets ${DB_CONNECTION_SECRET} -o json)
POSTGRES_USER=$(echo "${DB_SECRET}" | jq -r '.data.username' | base64 --decode)
POSTGRES_PASSWORD=$(echo "${DB_SECRET}" | jq -r '.data.password' | base64 --decode)
POSTGRES_CONNECTION_STRING="postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@localhost:${PORT}/${POSTGRES_DB}"

echo " - Port forwarding remote PostgreSQL to port ${PORT}."
echo "   You can use ${POSTGRES_CONNECTION_STRING} to run psql"
kubectl ${K8S_NAMESPACE} port-forward ${POD_NAME} ${PORT}:5432
