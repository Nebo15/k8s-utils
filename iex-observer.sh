#!/bin/bash
# This script provides easy way to debug remote Erlang nodes that is running in a Kubernetes cluster.
#
# Application on remote node should include `:runtime_tools` in it's applications dependencies, otherwise
# you will receive `rpc:handle_call` error.
K8S_UTILS_DIR="${BASH_SOURCE%/*}"
source ${K8S_UTILS_DIR}/helpers.sh

function show_help {
  echo "
  ktl iex:observer -lSELECTOR or -pPOD_NAME [-nNAMESPACE -h]

  Connect local IEx session to a remote running Erlang/OTP node and start an Observer application.

  If there are multuple pods that match the selector - random one is choosen.

  Examples:
    ktl iex:observer -lapp=hammer-web                Connect to one of the pods of hammer-web application in default namespace.
    ktl iex:observer -lapp=hammer-web -nweb          Connect to one of the pods of hammer-web application in web namespace.
    ktl iex:observer -phammer-web-kfjsu-3827 -nweb   Connect to hammer-web pod in web namespace.
"
}

POD_NAMESPACE=""
POD_NAME=
K8S_SELECTOR=

# Read configuration from CLI
while getopts "n:l:p:h" opt; do
  case "$opt" in
    n)  POD_NAMESPACE=${OPTARG}
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

if [[ $UID != 0 ]]; then
  error "Please run this script with sudo: sudo ktl iex:observer $*"
fi

if [[ ! $K8S_SELECTOR && ! $POD_NAME ]]; then
  error "You need to specify Kubernetes selector with '-l' option or pod name via '-p' option."
fi

if [ ! $POD_NAME ]; then
  POD_NAME=$(fetch_pod_name "${POD_NAMESPACE}" "${K8S_SELECTOR}")
fi

if [ ! $POD_NAMESPACE ]; then
  POD_NAMESPACE=$(get_pod_namespace "${POD_NAME}")
fi

LOCAL_DIST_PORT=$(get_free_random_port)
ERLANG_COOKIE=$(get_erlang_cookie "${POD_NAMESPACE}" "${POD_NAME}")
POD_DNS=$(get_pod_dns_record "${POD_NAMESPACE}" "${POD_NAME}")
EPMD_NAMES=$(get_epmd_names "${POD_NAMESPACE}" "${POD_NAME}")
RELEASE_NAME=$(ger_erlang_release_name_from_epmd_names "${EPMD_NAMES}")
ERLANG_DISTRIBUTION_PORTS=$(get_erlang_distribution_ports_from_epmd_names "${EPMD_NAMES}")

tunnel_erlang_distribution_connections "${POD_NAMESPACE}" "${POD_NAME}" "${POD_DNS}" "${LOCAL_DIST_PORT}" "${ERLANG_DISTRIBUTION_PORTS}"

log_step "You can use following node name to manually connect to it in Observer: "
banner "${RELEASE_NAME}@${POD_DNS}"

log_step "Connecting to ${RELEASE_NAME} on ports ${ERLANG_DISTRIBUTION_PORTS} with cookie '${ERLANG_COOKIE}'."

WHOAMI=$(whoami)
# Run observer in hidden mode to avoid hurting cluster's health
iex \
  --name "debug-remsh-${WHOAMI}@${POD_DNS}" \
  --cookie "${ERLANG_COOKIE}" \
  --erl "-start_epmd false" \
  --hidden \
  -e ":observer.start()"
