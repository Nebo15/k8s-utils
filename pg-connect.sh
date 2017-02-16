#!/bin/bash
# This script provides easy way to connect to remote postgres DB.
# Example: ./bin/pg-connect.sh -n mp -l app=postgres
set -e

K8S_SELECTOR="app=postgres"

# Read configuration from CLI
while getopts "n:l:c:" opt; do
  case "$opt" in
    n)  K8S_NAMESPACE="--namespace=${OPTARG}"
        ;;
    l)  K8S_SELECTOR=${OPTARG}
        ;;
  esac
done

# Required part of config
if [ ! $K8S_SELECTOR ]; then
  echo "[E] You need to specify Kubernetes selector with '-l' option."
  exit 1
fi

POD=$(kubectl get pods -l ${K8S_SELECTOR} ${K8S_NAMESPACE} \
  -o template --template="{{range.items}}{{.metadata.name}}{{end}}")

if [ ! $POD ]; then
  echo "[E] Pod wasn't found. Try to select it with -n (namespace) and -l options."
  exit 1
fi

echo "Found pod ${POD}."
kubectl ${K8S_NAMESPACE} port-forward ${POD} 5433:5432
