#!/bin/bash
# This script provides easy way to debug remote Erlang nodes that is running in a Kubernetes cluster.
#
# Application on remote node should include `:runtime_tools` in it's applications dependencies, otherwise
# you will receive `rpc:handle_call` error.
set -e

function show_help {
  echo "
  ktl iex:shell -lSELECTOR or -pPOD_NAME [-nNAMESPACE -cCOOKIE -h]

  Connect to a IEx shell of running Erlang/OTP node. Shell is executed wihin the pod.

  If there are multuple pods that match the selector - random one is choosen.

  Examples:
    ktl iex:shell -lapp=hammer-web           Connect to one of the pods of hammer-web application in default namespace.
    ktl iex:shell -lapp=hammer-web -nweb     Connect to one of the pods of hammer-web application in web namespace.
    ktl iex:shell -lapp=hammer-web -cfoo     Connect to one of the pods of hammer-web application with cookie foo.
"
}

K8S_NAMESPACE=
POD_NAME=
K8S_SELECTOR=
ERL_COOKIE=

# Read configuration from CLI
while getopts "n:l:p:c:h" opt; do
  case "$opt" in
    n)  K8S_NAMESPACE=${OPTARG}
        ;;
    l)  K8S_SELECTOR=${OPTARG}
        ;;
    c)  ERL_COOKIE=${OPTARG}
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
  echo "[E] You need to specify Kubernetes selector with '-l' option or pod name via '-p' option."
  exit 1
fi

if [ ! $POD_NAME ]; then
  echo " - Selecting pod with '-l ${K8S_SELECTOR} --namespace=${K8S_NAMESPACE}' selector."
  POD_NAME=$(
    kubectl get pods --namespace=${K8S_NAMESPACE} \
      -l ${K8S_SELECTOR} \
      -o jsonpath='{range .items[*]}
                   {@.metadata.name}:{range @.status.conditions[*]}{@.type}={@.status};{end}{end}' \
      | grep 'Ready=True' \
      | awk -F: '{print $1}'
  )
fi

echo " - Entering shell on remote Erlang/OTP node."
kubectl exec ${POD_NAME} --namespace=${K8S_NAMESPACE} \
  -it \
  -- /bin/sh -c 'bin/${APPLICATION_NAME} remote_console'
