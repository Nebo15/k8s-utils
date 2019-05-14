#!/bin/bash
set -em

function show_help {
  echo "
  ktl pg:outliers -linstance_name=staging -dtalkinto [-nkube-system -h -r -t -n]

  Show queries that have longest execution time in aggregate. Requires pg_stat_statements.

  If you get ERROR:  42P01: relation \"pg_stat_statements\" does not exist, then pg_stat_statements
  extension is not enabled. To enable it run execute \"CREATE EXTENSION pg_stat_statements\".

  Options:
    -lSELECTOR          Selector for a pod that exposes PostgreSQL instance. Required.
    -nNAMESPACE         Namespace for a pod that exposes PostgreSQL instance. Default: kube-system.
    -dpostgres          Database name to use. Required.
    -h                  Show help and exit.
    -t                  Do not truncate queries to 40 characters.
    -r                  Resets statistics gathered by pg_stat_statements.
    -c10                Number of queries to display. Default: 10.

  Examples:
    ktl pg:outliers -linstance_name=staging -dtalkinto
    ktl pg:outliers -linstance_name=staging -dtalkinto -r -c10 -t

  Available databases:
"

  ktl get pods -n kube-system -l proxy_to=google_cloud_sql --all-namespaces=true -o json \
    | jq -r '.items[] | "\(.metadata.namespace)\t\(.metadata.name)\t\(.metadata.labels.instance_name)\tktl pg:outliers -n \(.metadata.namespace) -l instance_name=\(.metadata.labels.instance_name) -d $DB_NAME"' \
    | awk -v FS="," 'BEGIN{print "    Namespace\tPod Name\tCloud SQL Instance_Name\tktl command";}{printf "    %s\t%s\t%s\t%s%s",$1,$2,$3,$4,ORS}' \
    | column -ts $'\t'
}

K8S_NAMESPACE="--namespace=kube-system"
PORT=$(awk 'BEGIN{srand();print int(rand()*(63000-2000))+2000 }')
RESET=""
NUMBER=10
TRUNCATE="CASE WHEN length(query) <= 40 THEN query ELSE substr(query, 0, 39) || '…' END"

# Read configuration from CLI
while getopts "hn:l:p:rn:td:" opt; do
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
    r)  RESET="true"
        ;;
    n)  NUMBER="${OPTARG}"
        ;;
    t)  TRUNCATE="query"
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

if [[ "${RESET}" == "true" ]]; then
  psql "${POSTGRES_CONNECTION_STRING}" --no-psqlrc --command "SELECT pg_stat_statements_reset();"
fi

psql "${POSTGRES_CONNECTION_STRING}" --no-psqlrc --command "
  SELECT
    rolname AS rolname,
    interval '1 millisecond' * total_time AS total_exec_time,
    to_char((total_time/sum(total_time) OVER()) * 100, 'FM90D0') || '%' AS prop_exec_time,
    mean_time,
    max_time,
    stddev_time,
    interval '1 millisecond' * (blk_read_time + blk_write_time) AS sync_io_time,
    rows,
    to_char(calls, 'FM999G999G999G990') AS ncalls,
    regexp_replace(${TRUNCATE}, '[ \t\n]+', ' ', 'g') AS query
  FROM pg_stat_statements
  JOIN pg_roles r ON r.oid = userid
  WHERE userid = (SELECT usesysid FROM pg_user WHERE usename = current_user LIMIT 1)
  ORDER BY total_time DESC
  LIMIT ${NUMBER}
"
