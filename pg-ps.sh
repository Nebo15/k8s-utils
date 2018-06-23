#!/bin/bash
set -em

function show_help {
  echo "
  ktl pg:psql [-lapp=db -ndefault -h -dpostgres -v]

  View active queries with execution time.

  Options:
    -lSELECTOR          Selector for a pod that exposes PostgreSQL instance. Default: app=db.
    -nNAMESPACE         Namespace for a pod that exposes PostgreSQL instance. Default: default.
    -dpostgres          Database name to use. Default: postgres.
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
POSTGRES_DB="postgres"
VERBOSE="AND state <> 'idle'"

# Read configuration from CLI
while getopts "hn:l:p:d:v" opt; do
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
    v)  VERBOSE=""
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

sleep 2

WAIT_RAND=$(awk 'BEGIN{srand();print int(rand()*(63000-2000))+2000 }')
WAIT_RETURN=$(
  psql "${POSTGRES_CONNECTION_STRING}" --command "SELECT '${WAIT_RAND}' || '${WAIT_RAND}' WHERE EXISTS (
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

psql "${POSTGRES_CONNECTION_STRING}" --command "
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
