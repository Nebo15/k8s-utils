#!/bin/bash
set -em

function show_help {
  echo "
  ktl pg:psql -p3443 -dpostgres [-lapp=db -ndefault -h -f]

  Kill a query by pid.

  Options:
    -lSELECTOR          Selector for a pod that exposes PostgreSQL instance. Default: app=db.
    -nNAMESPACE         Namespace for a pod that exposes PostgreSQL instance. Default: default.
    -dpostgres          Database name to use. Default: postgres.
    -pPID               Query PID.
    -f                  Force kill.
    -h                  Show help and exit.
    -v                  Verbose output, includes idle transactions.

  Examples:
    ktl pg:psql
    ktl pg:psql -lapp=readonly-db
    ktl pg:psql -lapp=readonly-db -p5433
"
}

K8S_SELECTOR="app=db"
PORT=$(awk 'BEGIN{srand();print int(rand()*(63000-2000))+2000 }')
COMMAND="pg_cancel_backend"

# Read configuration from CLI
while getopts "hn:l:p:d:fp:" opt; do
  case "$opt" in
    n)  K8S_NAMESPACE="--namespace=${OPTARG}"
        ;;
    l)  K8S_SELECTOR="${OPTARG}"
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

if [[ "${POSTGRES_DB}" == "" ]]; then
  echo "PostgreSQL database is not set, use -d option"
  exit 1
fi

if [[ "${PID}" == "" ]]; then
  echo "PostgreSQL query PID is not set, use -p option"
  exit 1
fi

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
POSTGRES_USER=$(echo "${DB_SECRET}" | jq -r '.data.username' | base64 -D)
POSTGRES_PASSWORD=$(echo "${DB_SECRET}" | jq -r '.data.password' | base64 -D)
POSTGRES_CONNECTION_STRING="postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@localhost:${PORT}/${POSTGRES_DB}"

# Trap exit so we can try to kill proxies that has stuck in background
function cleanup {
  kill $! &> /dev/null
  kill %1 &> /dev/null
}
trap cleanup EXIT

echo " - Port forwarding remote PostgreSQL to localhost port ${PORT}."
kubectl ${K8S_NAMESPACE} port-forward ${POD_NAME} ${PORT}:5432 &> /dev/null &

for i in `seq 1 30`; do
  [[ "${i}" == "30" ]] && echo "Failed waiting for port forward" && exit 1
  nc -z localhost ${PORT} && break
  echo -n .
  sleep 1
done

psql "${POSTGRES_CONNECTION_STRING}" --command "SELECT ${COMMAND}(${PID});"
