#!/bin/bash
# This script provides easy way to debug remote Erlang nodes that is running in a Kubernetes cluster.
#
# Application on remote node should include `:runtime_tools` in it's applications dependencies, otherwise
# you will receive `rpc:handle_call` error.
K8S_UTILS_DIR="${BASH_SOURCE%/*}"
source ${K8S_UTILS_DIR}/helpers.sh

function show_help {
  echo "
  ktl iex:shell -lSELECTOR or -pPOD_NAME [-nNAMESPACE -h]

  Connect to a IEx shell of running Erlang/OTP node. Shell is executed wihin the pod.

  If there are multuple pods that match the selector - random one is choosen.

  Examples:
    ktl iex:shell -lapp=hammer-web                Connect to one of the pods of hammer-web application in default namespace.
    ktl iex:shell -lapp=hammer-web -nweb          Connect to one of the pods of hammer-web application in web namespace.
    ktl iex:shell -phammer-web-kfjsu-3827 -nweb   Connect to hammer-web pod in web namespace.
"
}

K8S_NAMESPACE=""
POD_NAME=
K8S_SELECTOR=

# Read configuration from CLI
while getopts "n:l:p:h" opt; do
  case "$opt" in
    n)  K8S_NAMESPACE=${OPTARG}
        ;;
    l)  K8S_SELECTOR=${OPTARG}
        ;;
    p)  POD_NAME=${OPTARG}
        ;;
    h)  show_help
        exit 0
        ;;
  esac
done

# Required part of config
if [[ ! $K8S_SELECTOR && ! $POD_NAME ]]; then
  error "You need to specify Kubernetes selector with '-l' option or pod name via '-p' option."
fi

if [ ! $POD_NAME ]; then
  POD_NAME=$(fetch_pod_name "${K8S_NAMESPACE}" "${K8S_SELECTOR}")
fi

if [ ! $K8S_NAMESPACE ]; then
  K8S_NAMESPACE=$(get_pod_namespace "${POD_NAME}")
fi

log_step "Entering shell on remote Erlang/OTP node."
log_step "Pod ${POD_NAME} in namespace ${K8S_NAMESPACE}"
kubectl exec ${POD_NAME} --namespace=${K8S_NAMESPACE} \
  -it \
  -- /bin/sh -c 'bin/${APPLICATION_NAME} remote'
