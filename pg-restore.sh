#!/bin/bash
set -em

function show_help {
  echo "
  ktl pg:restore -linstance_name=staging -dtalkinto [-nkube-system -h -eschema_migrations -tapis,plugins -f dumps/ -dpostgres]

  Restores PostgreSQL database from a local directory (in binary format).

  Options:
    -lSELECTOR          Selector for a pod that exposes PostgreSQL instance. Required.
    -nNAMESPACE         Namespace for a pod that exposes PostgreSQL instance. Default: kube-system.
    -dpostgres          Database name. Required.
    -t                  List of tables to export. By default all tables are exported. Comma delimited.
    -e                  List of tables to exclude from export. Comma delimited. By default no tables are ignored.
    -f                  Path to directory where dumps are stored. By default: ./dumps
    -h                  Show help and exit.

  Examples:
    ktl pg:restore -dtalkinto -linstance_name=staging
    ktl pg:restore -dtalkinto -linstance_name=staging -eschema_migrations
    ktl pg:restore -dtalkinto -linstance_name=staging -tapis,plugins,requests

  Available databases:
"

  ktl get pods -n kube-system -l proxy_to=google_cloud_sql --all-namespaces=true -o json \
    | jq -r '.items[] | "\(.metadata.namespace)\t\(.metadata.name)\t\(.metadata.labels.instance_name)\tktl pg:restore -n \(.metadata.namespace) -l instance_name=\(.metadata.labels.instance_name) -d $DATABASE_NAME"' \
    | awk -v FS="," 'BEGIN{print "    Namespace\tPod Name\tCloud SQL Instance_Name\tktl command";}{printf "    %s\t%s\t%s\t%s%s",$1,$2,$3,$4,ORS}' \
    | column -ts $'\t'
}

K8S_NAMESPACE="--namespace=kube-system"
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
  echo "[Error] Port ${PORT} is busy, try to specify different port name with -p option."
  exit 1
fi
set -e

if [[ ! -e "${DUMP_PATH}/${POSTGRES_DB}" ]]; then
  echo "[Error] ${DUMP_PATH}/${POSTGRES_DB} does not exist, specify backup path with -f option"
  exit 1
fi

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
  set +x
  echo " - Stopping port forwarding."
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

echo " - Restoring remote ${POSTGRES_DB} DB from ./dumps/${POSTGRES_DB}"
set -x
pg_restore dumps/${POSTGRES_DB} \
  -h localhost \
  -p ${PORT} \
  -U ${POSTGRES_USER} \
  -d ${POSTGRES_DB} \
  --verbose \
  --no-acl \
  --no-owner \
  --format c ${TABLES} ${EXCLUDE_TABLES}
set +x
