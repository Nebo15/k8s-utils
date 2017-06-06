#!/bin/bash
# This script backups all critical data, allowing to move it from one environment to another
set -em

# Trap exit so we can try to kill proxies that has stuck in background
function cleanup {
  echo " - Stopping ktl port forwarding."
  kill $! &> /dev/null
  kill %1 &> /dev/null
}
trap cleanup EXIT

K8S_SELECTOR="app=postgresql"
K8S_NAMESPACE=""
TABLES=""

# Read configuration from CLI
while getopts "n:l:t:dr" opt; do
  case "$opt" in
    n)  K8S_NAMESPACE="-n${OPTARG}"
        ;;
    l)  K8S_SELECTOR=${OPTARG}
        ;;
    t)  TABLES=${OPTARG}
        TABLES="--table=${TABLES//,/ --table=}"
        ;;
    d)  DUMP="true"
        ;;
    r)  RESTORE="true"
        ;;
  esac
done

if [[ "${DUMP}" == "true" && "${RESTORE}" == "true" ]]; then
  echo "[ERROR] Dump and restore are mutually exclusive options."
  exit 1
elif [[ ! $DUMP && ! $RESTORE ]]; then
  echo "[ERROR] You need to specify type of operation: '-d' - dump DB, '-r' - restore DB."
  exit 1
fi;

echo " - Connecting to a DB"
POD_NAME=$(kubectl get pods -l ${K8S_SELECTOR} ${K8S_NAMESPACE} -o template --template="{{range.items}}{{.metadata.name}}{{end}}")

kubectl ${K8S_NAMESPACE} port-forward ${POD_NAME} 5433:5432 &

sleep 1

echo " - Resolving DB user."
POSTGRES_USER=$(kubectl get pod ${POD_NAME} ${K8S_NAMESPACE} -o jsonpath='{$.spec.containers[0].env[?(@.name=="POSTGRES_USER")].value}')
echo " - Resolving DB password."
POSTGRES_PASSWORD=$(kubectl get pod ${POD_NAME} ${K8S_NAMESPACE} -o jsonpath='{$.spec.containers[0].env[?(@.name=="POSTGRES_PASSWORD")].value}')
echo " - Resolving DB name."
POSTGRES_DB=$(kubectl get pod ${POD_NAME} ${K8S_NAMESPACE} -o jsonpath='{$.spec.containers[0].env[?(@.name=="POSTGRES_DB")].value}')

export PGPASSWORD="$POSTGRES_PASSWORD"

echo " - Dump will be stored in ./dumps/${POSTGRES_DB}"
mkdir -p "./dumps/${POSTGRES_DB}"

if [[ "${DUMP}" == "true" ]]; then
  echo " - Dumping DB to ./dumps/${POSTGRES_DB}"

  pg_dump ${POSTGRES_DB} -h localhost -p 5433 -U ${POSTGRES_USER} --data-only --format directory --file dumps/${POSTGRES_DB} ${TABLES}
elif [[ "${RESTORE}" == "true" ]]; then
  echo " - Restoring DB from ./dumps/${POSTGRES_DB}"

  pg_restore dumps/${POSTGRES_DB} -h localhost -p 5433 -U ${POSTGRES_USER} -d ${POSTGRES_DB} --data-only --format directory ${TABLES}
fi;

echo " - Returning control over port-forward"
fg
