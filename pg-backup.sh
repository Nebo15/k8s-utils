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
    n)  K8S_NAMESPACE="${OPTARG}"
        ;;
    l)  K8S_SELECTOR=${OPTARG}
        ;;
    t)  TABLES="--table=${OPTARG}"
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
ktl connect -n${K8S_NAMESPACE} -l${K8S_SELECTOR} &> /dev/null &

sleep 5

echo " - Dump will be stored in ./dumps/${K8S_NAMESPACE}"
mkdir -p "./dumps/${K8S_NAMESPACE}"

if [[ "${DUMP}" == "true" ]]; then
  echo " - Dumping DB to ./dumps/${K8S_NAMESPACE}"

  pg_dump ${K8S_NAMESPACE} -h localhost -p 5433 -U postgres --data-only --format directory --file dumps/${K8S_NAMESPACE} ${TABLES}
elif [[ "${RESTORE}" == "true" ]]; then
  echo " - Restoring DB from ./dumps/${K8S_NAMESPACE}"

  pg_restore dumps/${K8S_NAMESPACE} -h localhost -p 5433 -U postgres --data-only --format directory ${TABLES}
fi;

echo " - Returning control over port-forward"
fg
