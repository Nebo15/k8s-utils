#!/bin/bash
set -em

function show_help {
  echo "
  ktl pg:proxy -linstance_name=staging [-nkube-system -h -p5432 -dpostgres]

  Proxy PostgresSQL port to localhost.

  Options:
    -lSELECTOR          Selector for a pod that exposes PostgreSQL instance. Required.
    -nNAMESPACE         Namespace for a pod that exposes PostgreSQL instance. Default: kube-system.
    -pPORT              Local port for forwarding. Default: 5432.
    -dpostgres          Database name to use.
    -h                  Show help and exit.

  Examples:
    ktl pg:proxy -linstance_name=staging
    ktl pg:proxy -linstance_name=staging -p5433

  Available databases:\
"

  ktl get pods -n kube-system -l proxy_to=google_cloud_sql --all-namespaces=true -o json \
    | jq -r '.items[] | "\(.metadata.namespace)\t\(.metadata.name)\t\(.metadata.labels.instance_name)\tktl pg:proxy -n \(.metadata.namespace) -l instance_name=\(.metadata.labels.instance_name) -p5433"' \
    | awk -v FS="," 'BEGIN{print "    Namespace\tPod Name\tCloud SQL Instance_Name\tktl command";}{printf "    %s\t%s\t%s\t%s%s",$1,$2,$3,$4,ORS}' \
    | column -ts $'\t'
}

PORT="5432"
POSTGRES_DB="postgres"
K8S_NAMESPACE="--namespace=kube-system"

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

if [[ "${K8S_SELECTOR}" == "" ]]; then
  echo "[E] Pod selector is not set. Use -n (namespace) and -l options or -h to list available databases."
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
  echo "[W] Can not automatically resolve DB connection secret."
else
  echo " - Automatically resolving connection url from connection secret in cluster."
  POSTGRES_USER=$(echo "${DB_CONNECTION_SECRET}" | jq -r '.data.username' | base64 --decode)
  POSTGRES_PASSWORD=$(echo "${DB_CONNECTION_SECRET}" | jq -r '.data.password' | base64 --decode)
  POSTGRES_CONNECTION_STRING="postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@localhost:${PORT}/${POSTGRES_DB}"
  echo "   You can use 'psql ${POSTGRES_CONNECTION_STRING}' command to connect to database"
fi

echo " - Port forwarding remote PostgreSQL to port ${PORT}."
kubectl ${K8S_NAMESPACE} port-forward ${POD_NAME} ${PORT}:5432
