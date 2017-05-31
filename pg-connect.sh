#!/bin/bash
# This script provides easy way to connect to remote postgres DB.
# Example: ./bin/pg-connect.sh -n mp -l app=postgres
set -em

K8S_SELECTOR="app=postgresql"
RUN_PSQL="false"

# Read configuration from CLI
while getopts "n:l:qc:" opt; do
  case "$opt" in
    n)  K8S_NAMESPACE="--namespace=${OPTARG}"
        ;;
    l)  K8S_SELECTOR=${OPTARG}
        ;;
    q)  RUN_PSQL="true"
        ;;
  esac
done

# Required part of config
if [ ! $K8S_SELECTOR ]; then
  echo "[E] You need to specify Kubernetes selector with '-l' option."
  exit 1
fi

POD_NAME=$(kubectl get pods -l ${K8S_SELECTOR} ${K8S_NAMESPACE} \
  -o template --template="{{range.items}}{{.metadata.name}}{{end}}")

if [ ! ${POD_NAME} ]; then
  echo "[E] Pod wasn't found. Try to select it with -n (namespace) and -l options."
  exit 1
fi

echo " - Found pod ${POD_NAME}."
if [[ "${RUN_PSQL}" == "true" ]]; then
  echo " - Attaching to a psql CLI on remote host (type '\q' to exit)."
  kubectl exec ${K8S_NAMESPACE} ${POD_NAME} -it -- /bin/sh -c 'psql -U ${POSTGRES_USER} ${POSTGRES_DB}'
else
  # Trap exit so we can try to kill proxies that has stuck in background
  function cleanup {
    echo " - Stopping ktl port forwarding."
    kill $! &> /dev/null
    kill %1 &> /dev/null
  }
  trap cleanup EXIT

  echo " - Resolving DB user."
  POSTGRES_USER=$(kubectl get pod ${POD_NAME} ${K8S_NAMESPACE} -o jsonpath='{$.spec.containers[0].env[?(@.name=="POSTGRES_USER")].value}')
  echo " - Resolving DB password."
  POSTGRES_PASSWORD=$(kubectl get pod ${POD_NAME} ${K8S_NAMESPACE} -o jsonpath='{$.spec.containers[0].env[?(@.name=="POSTGRES_PASSWORD")].value}')
  echo " - Resolving DB name."
  POSTGRES_DB=$(kubectl get pod ${POD_NAME} ${K8S_NAMESPACE} -o jsonpath='{$.spec.containers[0].env[?(@.name=="POSTGRES_DB")].value}')

  echo " - Port forwarding remote PostreSQL to port 5433."
  kubectl ${K8S_NAMESPACE} port-forward ${POD_NAME} 5433:5432 &

  sleep 1

  echo " - Open PG CLI: open postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@localhost:5433/${POSTGRES_DB}"
  open "postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@localhost:5433/${POSTGRES_DB}"

  echo " - Returning control over port-forward"
  fg
fi;
