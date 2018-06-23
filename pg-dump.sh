#!/bin/bash
set -em

function show_help {
  echo "
  ktl pg:dump [-lapp=db -ndefault -h -o -dpostgres]

  Dumps PostgreSQL database to local directory in binary format.

  Options:
    -lSELECTOR          Selector for a pod that exposes PostgreSQL instance. Default: app=db.
    -nNAMESPACE         Namespace for a pod that exposes PostgreSQL instance. Default: default.
    -dpostgres          Database name when -o flag is set.
    -t                  List of tables to export. By default all tables are exported. Comma delimited.
    -e                  List of tables to exclude from export. Comma delimited. By default no tables are ignored.
    -f                  Path to directory where dump would be stored. By default: ./dumps
    -h                  Show help and exit.

  Examples:
    ktl pg:dump
    ktl pg:dump -lapp=readonly-db
    ktl pg:dump -lapp=readonly-db -eschema_migrations
    ktl pg:dump -lapp=readonly-db -tapis,plugins,requests
"
}

K8S_SELECTOR="app=db"
PORT=$(awk 'BEGIN{srand();print int(rand()*(63000-2000))+2000 }')
POSTGRES_DB="postgres"
DUMP_PATH="./dumps"
TABLES=""
EXCLUDE_TABLES=""

# Read configuration from CLI
while getopts "hn:l:p:d:t:e:t:f:e:" opt; do
  case "$opt" in
    n)  K8S_NAMESPACE="--namespace=${OPTARG}"
        ;;
    l)  K8S_SELECTOR="${OPTARG}"
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
  esac
done

set +e
nc -z localhost ${PORT} < /dev/null
if [[ $? == "0" ]]; then
  echo "[Error] Port ${PORT} is busy, try to specify different port name with -p option."
  exit 1
fi
set -e

if [[ -e "${DUMP_PATH}/${POSTGRES_DB}" ]]; then
  echo "[Error] ${DUMP_PATH}/${POSTGRES_DB} already exists, delete it or specify another path with -f option"
  exit 1
fi

echo " - Selecting pod with '-l ${K8S_SELECTOR} -n ${K8S_NAMESPACE:-default}' selector."
SELECTED_PODS=$(
  kubectl get pods ${K8S_NAMESPACE} \
    -l ${K8S_SELECTOR} \
    -o json \
    --field-selector=status.phase=Running
)
POD_NAME=$(echo ${SELECTED_PODS} | jq -r '.items[0].metadata.name')

if [ ! ${POD_NAME} ]; then
  echo "[Error] Pod wasn't found. Try to select it with -n (namespace) and -l options."
  exit 1
fi

echo " - Found pod ${POD_NAME}."

# Trap exit so we can try to kill proxies that has stuck in background
function cleanup {
  set +x
  echo " - Stopping port forwarding."
  kill $! &> /dev/null
  kill %1 &> /dev/null
}
trap cleanup EXIT

echo " - Port forwarding remote PostgreSQL to localhost port ${PORT}."
kubectl ${K8S_NAMESPACE} port-forward ${POD_NAME} ${PORT}:5432 &> /dev/null &

DB_CONNECTION_SECRET=$(echo ${SELECTED_PODS} | jq -r '.items[0].metadata.labels.connectionSecret')
echo " - Resolving database user and password from secret ${DB_CONNECTION_SECRET}."
DB_SECRET=$(kubectl get secrets ${DB_CONNECTION_SECRET} -o json)
POSTGRES_USER=$(echo "${DB_SECRET}" | jq -r '.data.username' | base64 -D)
POSTGRES_PASSWORD=$(echo "${DB_SECRET}" | jq -r '.data.password' | base64 -D)

sleep 1

echo " - Dump will be stored in ${DUMP_PATH}/${POSTGRES_DB}"
mkdir -p "${DUMP_PATH}/"

echo " - Dumping ${POSTGRES_DB} DB to ${DUMP_PATH}/${POSTGRES_DB}"
set -x
PGPASSWORD="$POSTGRES_PASSWORD" \
pg_dump ${POSTGRES_DB} \
  -h localhost \
  -p ${PORT} \
  -U ${POSTGRES_USER} \
  --format c \
  --compress 0 \
  --file ${DUMP_PATH}/${POSTGRES_DB} ${TABLES} ${EXCLUDE_TABLES} \
  --verbose

set +x
