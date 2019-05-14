#!/bin/bash
set -em

function show_help {
  echo "
  ktl pg:ps -linstance_name=staging -dtalkinto [-nkube-system -h -v]

  View active queries with execution time.

  Options:
    -lSELECTOR          Selector for a pod that exposes PostgreSQL instance. Required.
    -nNAMESPACE         Namespace for a pod that exposes PostgreSQL instance. Default: kube-system.
    -dpostgres          Database name to use. Required.
    -h                  Show help and exit.
    -v                  Verbose output, includes idle transactions.

  Examples:
    ktl pg:ps -linstance_name=staging -dtalkinto

  Available databases:
"

  ktl get pods -n kube-system -l proxy_to=google_cloud_sql --all-namespaces=true -o json \
    | jq -r '.items[] | "\(.metadata.namespace)\t\(.metadata.name)\t\(.metadata.labels.instance_name)\tktl pg:ps -n \(.metadata.namespace) -l instance_name=\(.metadata.labels.instance_name) -d $DATABASE_NAME"' \
    | awk -v FS="," 'BEGIN{print "    Namespace\tPod Name\tCloud SQL Instance_Name\tktl command";}{printf "    %s\t%s\t%s\t%s%s",$1,$2,$3,$4,ORS}' \
    | column -ts $'\t'
}

K8S_NAMESPACE="--namespace=kube-system"
PORT=$(awk 'BEGIN{srand();print int(rand()*(63000-2000))+2000 }')
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

if [[ "${K8S_SELECTOR}" == "" ]]; then
  echo "[E] Pod selector is not set. Use -n (namespace) and -l options or -h to list available databases."
  exit 1
fi

if [[ "${POSTGRES_DB}" == "" ]]; then
  echo "[E] Posgres database is not set, use -d option."
  exit 1
fi

set +e
nc -z localhost ${PORT} < /dev/null
if [[ $? == "0" ]]; then
  echo "[E] Port ${PORT} is busy, try to specify different port name with -p option."
  exit 1
fi
set -e

echo " - Selecting pod with '-l ${K8S_SELECTOR} ${K8S_NAMESPACE}' selector."
SELECTED_PODS=$(
  kubectl get pods ${K8S_NAMESPACE} \
    -l ${K8S_SELECTOR} \
    -o json \
    --field-selector=status.phase=Running
)
POD_NAME=$(echo ${SELECTED_PODS} | jq -r '.items[0].metadata.name')

if [[ "${POD_NAME}" == "null" ]]; then
  echo "[E] Pod is not found. Try to select it with -n (namespace) and -l options. Use -h to list available databases."
  exit 1
fi

echo " - Found pod ${POD_NAME}."

DB_CONNECTION_SECRET=$(
  kubectl get secrets --all-namespaces=true \
    -l "service=google_cloud_sql,${K8S_SELECTOR}" \
    -o json | jq -r '.items[0]'
)

if [[ "${DB_CONNECTION_SECRET}" == "null" ]]; then
  echo "[E] Can not automatically resolve DB connection secret."
  exit 1
else
  echo " - Automatically resolving connection url from connection secret in cluster."
  POSTGRES_USER=$(echo "${DB_CONNECTION_SECRET}" | jq -r '.data.username' | base64 --decode)
  POSTGRES_PASSWORD=$(echo "${DB_CONNECTION_SECRET}" | jq -r '.data.password' | base64 --decode)
  POSTGRES_CONNECTION_STRING="postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@localhost:${PORT}/${POSTGRES_DB}"
fi

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
