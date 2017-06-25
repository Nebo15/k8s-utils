#!/bin/bash
# This script provides easy way to debug remote Erlang nodes that is running in a Kubernetes cluster.
#
# Application on remote node should include `:runtime_tools` in it's applications dependencies, otherwise
# you will receive `rpc:handle_call` error.
set -e

REMSH="false"

# Read configuration from CLI
while getopts "n:l:c:r" opt; do
  case "$opt" in
    n)  K8S_NAMESPACE="--namespace=${OPTARG}"
        ;;
    l)  K8S_SELECTOR=${OPTARG}
        ;;
    c)  ERL_COOKIE=${OPTARG}
        ;;
    r)  REMSH="true"
        ;;
  esac
done

# Required part of config
if [ ! $K8S_SELECTOR ]; then
  echo "[E] You need to specify Kubernetes selector with '-l' option."
  exit 1
fi

echo " - Selecting pod with '-l ${K8S_SELECTOR} ${K8S_NAMESPACE:-default}' selector."
POD_NAME=$(kubectl get pods -l ${K8S_SELECTOR} ${K8S_NAMESPACE} -o jsonpath='{.items[0].metadata.name}')

if [[ "${REMSH}" == "true" ]]; then
  echo " - Entering CLI on remote node."
  kubectl exec ${POD_NAME} ${K8S_NAMESPACE} -it -- /bin/sh -c 'erl -name debug_cli@127.0.0.1 -setcookie ${ERLANG_COOKIE} -hidden -remsh $(epmd -names | tail -n 1 | awk '"'"'{print $2}'"'"')@${POD_IP}'
else
  # Trap exit so we can try to kill proxies that has stuck in background
  function cleanup {
    echo " - Stopping kubectl proxy."
    kill $! &> /dev/null
  }
  trap cleanup EXIT

  echo " - Resolving Erlang node port on a pod '${POD_NAME}'."
  EPMD_OUTPUT=$(echo ${POD_NAME} | xargs -o -I my_pod kubectl exec my_pod ${K8S_NAMESPACE} -i -t -- epmd -names | tail -n 1)
  eval 'EPMD_OUTPUT=($EPMD_OUTPUT)'

  # By default, cookie is the same as node name
  if [ ! $ERL_COOKIE ]; then
    echo " - Resolving Erlang cookie from pod '${POD_NAME}' environment variables."
    ERL_COOKIE=$(kubectl get pod ${POD_NAME} ${K8S_NAMESPACE} -o jsonpath='{$.spec.containers[0].env[?(@.name=="ERLANG_COOKIE")].value}')
  fi

  # Strip newlines from last element of output
  OTP_PORT=${EPMD_OUTPUT[4]//[$'\t\r\n ']}

  echo " - Connecting on port ${OTP_PORT} with cookie '${ERL_COOKIE}'."

  # Kill epmd on local node to free 4369 port
  killall epmd &> /dev/null || true

  # Replace it with remote nodes epmd and proxy remove erlang app port
  echo " - Running: kubectl port-forward $POD_NAME $K8S_NAMESPACE 4369 $OTP_PORT &> /dev/null &"
  kubectl port-forward $POD_NAME $K8S_NAMESPACE 4369 $OTP_PORT &> /dev/null &

  # Give some time for tunnel to be established
  sleep 1

  # Run observer in hidden mode to avoid hurting cluster's health
  echo " - Running: erl -start_epmd false -name debug@127.0.0.1 -setcookie $ERL_COOKIE -hidden -run observer"
  erl -start_epmd false -name debug@127.0.0.1 -setcookie $ERL_COOKIE -hidden -run observer
fi;
