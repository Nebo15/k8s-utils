#!/bin/bash
# This script provides easy way to debug remote Erlang nodes that is running in a Kubernetes cluster.
#
# Application on remote node should include `:runtime_tools` in it's applications dependencies, otherwise
# you will receive `rpc:handle_call` error.
set -eo pipefail

K8S_NAMESPACE=
POD_NAME=
K8S_SELECTOR=
ERL_COOKIE=

# Read configuration from CLI
while getopts "n:l:p:c:r" opt; do
  case "$opt" in
    n)  K8S_NAMESPACE=${OPTARG}
        ;;
    l)  K8S_SELECTOR=${OPTARG}
        ;;
    c)  ERL_COOKIE=${OPTARG}
        ;;
    p)  POD_NAME=${OPTARG}
        ;;
  esac
done

K8S_NAMESPACE=${K8S_NAMESPACE:-default}

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
      -o jsonpath='{.items[0].metadata.name}' \
      --field-selector=status.phase=Running
  )
fi

APP_NAME=$(
  kubectl get pod ${POD_NAME} --namespace=${K8S_NAMESPACE} \
    -o jsonpath='{.metadata.labels.app}'
)

# Trap exit so we can try to kill proxies that has stuck in background
function cleanup {
  set +x
  sudo sed -i '' "/${HOST_RECORD}/d" /etc/hosts
  echo " - Stopping kubectl proxy."
  kill $! &> /dev/null
}
trap cleanup EXIT;

# By default, cookie is the same as node name
if [[ "${ERLANG_COOKIE}" == "" ]]; then
  echo " - Resolving Erlang cookie from pod '${POD_NAME}' environment variables."
  ERLANG_COOKIE=$(
    kubectl get pod ${POD_NAME} \
      --namespace=${K8S_NAMESPACE} \
      -o jsonpath='{$.spec.containers[0].env[?(@.name=="ERLANG_COOKIE")].value}'
  )
fi

echo " - Resolving pod ip from pod '${POD_NAME}' environment variables."
POD_IP=$(
  kubectl get pod ${POD_NAME} \
    --namespace=${K8S_NAMESPACE} \
    -o jsonpath='{$.status.podIP}'
)
POD_DNS=$(echo $POD_IP | sed 's/\./-/g')."${K8S_NAMESPACE}.pod.cluster.local"
HOST_RECORD="127.0.0.1 ${POD_DNS}"

echo " - Resolving Erlang node port and release name on a pod '${POD_NAME}'."
LOCAL_DIST_PORT=$(awk 'BEGIN{srand();print int(rand()*(63000-2000))+2000 }')
echo "   Using local port: ${LOCAL_DIST_PORT}"
DIST_PORTS=()
EPMD_OUTOUT=$(kubectl exec ${POD_NAME} --namespace=${K8S_NAMESPACE} -i -t -- epmd -names)
while read -r DIST_PORT; do
    DIST_PORT=$(echo "${DIST_PORT}" | sed 's/.*port //g; s/[^0-9]*//g')
    echo "   Found port: ${DIST_PORT}"
    DIST_PORTS+=(${DIST_PORT})
done <<< "${EPMD_OUTOUT}"
RELEASE_NAME=$(echo "${EPMD_OUTOUT}" | tail -n 1 | awk '{print $2;}')

echo " - Adding new record to /etc/hosts."
echo "${HOST_RECORD}" >> /etc/hosts

echo " - Connecting to ${RELEASE_NAME} on ports ${DIST_PORTS[@]} with cookie '${ERLANG_COOKIE}'."
# Kill epmd on local node to free 4369 port
killall epmd &> /dev/null || true

echo "+ kubectl port-forward ${POD_NAME} --namespace=${K8S_NAMESPACE} ${DIST_PORTS[@]} ${LOCAL_DIST_PORT} &> /dev/null &"
# Replace it with remote nodes epmd and proxy remove erlang app port
kubectl port-forward --namespace=${K8S_NAMESPACE} \
  ${POD_NAME} \
  ${DIST_PORTS[@]} \
  ${LOCAL_DIST_PORT} \
&> /dev/null &

echo "- Waiting for for tunnel to be established"
for i in `seq 1 30`; do
  [[ "${i}" == "30" ]] && echo "Failed waiting for port forward" && exit 1
  nc -z localhost ${LOCAL_DIST_PORT} && break
  echo -n .
  sleep 1
done

echo "- You can use following node name to manually connect to it in Observer: "
echo "  ${APP_NAME}@${POD_DNS}"

# Run observer in hidden mode to avoid hurting cluster's health
WHOAMI=$(whoami)
set -x

iex \
  --name "debug-remsh-${WHOAMI}@${POD_DNS}" \
  --cookie "${ERLANG_COOKIE}" \
  --erl "-start_epmd false -kernel inet_dist_listen_min ${LOCAL_DIST_PORT} inet_dist_listen_max ${LOCAL_DIST_PORT}" \
  --hidden \
  -e ":observer.start()"
set +x
