#!/bin/bash
set -meuo pipefail

PROJECT_ROOT_DIR=$(git rev-parse --show-toplevel)
OS=`uname`

function prepend() {
  while read line; do echo "${1}${line}"; done;
}

function log_step_append() {
  echo "$1" | prepend "  " >&2
}

function log_step() {
  echo "- $1" >&2
}

function log_step_with_progress() {
  echo -n "- $1" >&2
}

function log_progess_step() {
  echo -n "." >&2
}

function banner() {
  echo ""
  echo "  $1"
  echo ""
}

function error() {
  echo "[E] $1" >&2
  exit 1
}

function warning() {
  echo "[W] $1" >&2
}

# A basic wrapper for `sed` that works with both macOS and GNU versions
function delete_pattern_in_file {
  if [ "${OS}" = "Darwin" ]; then
    sudo sed -i '' "$1" "$2"
  else
    sudo sed -i "$1" "$2"
  fi
}

function replace_pattern_in_file {
  if [ "${OS}" = "Darwin" ]; then
    sed -E -i '' "$1" "$2"
  else
    sed -E -i "$1" "$2"
  fi
}

function fetch_pod_name() {
  NAMESPACE=$1
  SELECTOR=$2

  if [[ "${NAMESPACE}" = "" ]]; then
    NAMESPACE_OPT="--all-namespaces=true"
  else
    NAMESPACE_OPT="--namespace=${NAMESPACE}"
  fi

  log_step "Selecting pod with '${NAMESPACE_OPT} --selector=${SELECTOR}' options."

  POD_NAME=$(
    kubectl get pods ${NAMESPACE_OPT} \
      --selector="${SELECTOR}" \
      --field-selector='status.phase=Running' \
      --output="json" \
      | jq -r '.items[] | select((.status.conditions[] | select (.status == "True" and .type == "Ready"))) | .metadata.name' \
      | head -n 1
    )

  if [[ "${POD_NAME}" == "" || "${POD_NAME}" == "null" ]]; then
    error "Pod not found. Use -h for list of available selector options."
  else
    echo "${POD_NAME}"
  fi
}

# Pods

function get_pod_namespace() {
  POD_NAME=$1

  log_step "Getting pod ${POD_NAME} namespace"

  kubectl get pods --all-namespaces=true --output="json" \
    | jq -r ".items[] | select(.metadata.name == \"${POD_NAME}\") | .metadata.namespace"
}

function get_pod_ip_address() {
  NAMESPACE=$1
  POD_NAME=$2

  log_step "Getting pod ${POD_NAME} cluster IP address"

  kubectl get pod ${POD_NAME} --namespace="${NAMESPACE}" --output="json" \
    | jq -r '.status.podIP'
}

function get_pod_dns_record() {
  NAMESPACE=$1
  POD_NAME=$2

  POD_IP=$(get_pod_ip_address "${NAMESPACE}" "${POD_NAME}")
  echo $(echo "${POD_IP}" | sed 's/\./-/g')."${NAMESPACE}.pod.cluster.local"
}

# Networking

function get_free_random_port() {
  PORT=$(awk 'BEGIN{srand();print int(rand()*(63000-2000))+2000 }')
  if nc -z localhost ${PORT} < /dev/null; then
    echo $(get_random_port)
  else
    echo ${PORT}
  fi
}

function ensure_port_is_free() {
  PORT=$1

  if nc -z localhost ${PORT} < /dev/null; then
    error "Port ${PORT} is busy, try to specify different port number. Use -h for list of available selector options."
  else
    return 0
  fi
}

function is_port_free() {
  PORT=$1

  if nc -z localhost ${PORT} < /dev/null; then
    echo "false"
  else
    echo "true"
  fi
}

function wait_for_ports_to_become_busy() {
  PORT=$1

  log_step "Waiting for for ports ${PORT} to start responding"

  for i in `seq 1 30`; do
    [[ "${i}" == "30" ]] && error "Failed waiting for ports ${PORT} to start responding"
    nc -z localhost ${PORT} && break
    echo -n .
    sleep 1
  done
}

# Google Cloud SQL specific

function get_postgres_connection_url() {
  USER=$1
  PASSWORD=$2
  PORT=$3
  DB=$4

  echo "postgres://${USER}:${PASSWORD}@localhost:${PORT}/${DB}"
}

function get_postgres_user_password() {
  SQL_INSTANCE_NAME=$1
  POSTGRES_USER=$2

  log_step "Resolving PostgreSQL ${POSTGRES_USER} user password for Cloud SQL instance ${SQL_INSTANCE_NAME}"

  POSTGRES_USER_BASE64=$(printf "%s" "${POSTGRES_USER}" | base64)

  POSTGRES_PASSWORD=$(
    kubectl get secrets --all-namespaces=true \
      -l "service=google_cloud_sql,instance_name=${SQL_INSTANCE_NAME}" \
      -o json \
      | jq -r '.items[] | select(.data.username == "'${POSTGRES_USER_BASE64}'") | .data.password' \
      | base64 --decode
  )

  if [[ "${POSTGRES_PASSWORD}" == "" ]]; then
    error "Can not find secret with connection params for user ${POSTGRES_USER} at Cloud SQL instance ${SQL_INSTANCE_NAME}"
  else
    echo "${POSTGRES_PASSWORD}"
  fi
}

function list_sql_proxy_pods() {
  COMMAND=$1
  PADDING=${2:-""}

  ktl get pods -n kube-system -l proxy_to=google_cloud_sql --all-namespaces=true -o json \
    | jq -r ".items[] | \"\(.metadata.namespace)\t\(.metadata.name)\t\(.metadata.labels.instance_name)\t${COMMAND}\"" \
    | awk -v PADDING="$PADDING" -v FS="," 'BEGIN{print PADDING"Namespace\tPod Name\tCloud SQL Instance_Name\tktl command";}{printf PADDING"%s\t%s\t%s\t%s%s",$1,$2,$3,$4,ORS}' \
    | column -ts $'\t'
}

function list_sql_proxy_users() {
  COMMAND=$1
  PADDING=${2:-""}

  kubectl get secrets --all-namespaces=true \
    -l "service=google_cloud_sql" \
    -o json \
    | jq -r ".items[] | \"\(.metadata.namespace)\t\(.metadata.labels.instance_name)\t\(.data.username | @base64d)\t${COMMAND}\"" \
    | awk -v PADDING="$PADDING" -v FS="," 'BEGIN{print PADDING"Namespace\tCloud SQL Instance_Name\tUsername\tktl command";}{printf PADDING"%s\t%s\t%s\t%s%s",$1,$2,$3,$4,ORS}' \
    | column -ts $'\t'
}

function tunnel_postgres_connections() {
  PROXY_POD_NAMESPACE=$1
  PROXY_POD_NAME=$2
  PORT=$3

  # Trap exit so we can try to kill proxies that has stuck in background
  function cleanup {
    log_step "Stopping port forwarding."
    kill $! &> /dev/null
  }
  trap cleanup EXIT

  log_step "Port forwarding remote PostgreSQL to localhost port ${PORT}."
  kubectl --namespace="${PROXY_POD_NAMESPACE}" port-forward ${PROXY_POD_NAME} ${PORT}:5432 &> /dev/null &

  wait_for_ports_to_become_busy ${PORT}

  return 0
}

# Elixir/Erlang-specific

function get_erlang_cookie() {
  NAMESPACE=$1
  POD_NAME=$2

  log_step "Resolving Erlang cookie from secret linked to pod ${POD_NAME} variables."

  ERLANG_COOKIE_SECRET_NAME=$(
    kubectl get pod ${POD_NAME} \
      --namespace=${NAMESPACE} \
      -o jsonpath='{$.spec.containers[0].env[?(@.name=="ERLANG_COOKIE")].valueFrom.secretKeyRef.name}'
  )

  ERLANG_COOKIE_SECRET_KEY_NAME=$(
    kubectl get pod ${POD_NAME} \
      --namespace=${NAMESPACE} \
      -o jsonpath='{$.spec.containers[0].env[?(@.name=="ERLANG_COOKIE")].valueFrom.secretKeyRef.key}'
  )

  kubectl get secret ${ERLANG_COOKIE_SECRET_NAME} \
    --namespace=${NAMESPACE} \
    -o jsonpath='{$.data.'${ERLANG_COOKIE_SECRET_KEY_NAME}'}' | base64 --decode
}

function get_epmd_names() {
  NAMESPACE=$1
  POD_NAME=$2

  kubectl exec ${POD_NAME} --namespace="${NAMESPACE}" -i -t -- epmd -names
}

function ger_erlang_release_name_from_epmd_names() {
  log_step "Resolving Erlang release name"
  echo "$1" | tail -n 1 | awk '{print $2;}'
}

function get_erlang_distribution_ports_from_epmd_names() {
  log_step "Resolving ports used by Erlang distribution"

  while read -r DIST_PORT; do
    DIST_PORT=$(echo "${DIST_PORT}" | sed 's/.*port //g; s/[^0-9]*//g')
    log_step "   Found port: ${DIST_PORT}"
    DIST_PORTS+=(${DIST_PORT})
  done <<< "$1"

  echo "${DIST_PORTS[@]}"
}

function tunnel_erlang_distribution_connections() {
  POD_NAMESPACE=$1
  POD_NAME=$2
  POD_DNS=$3
  LOCAL_DIST_PORT=$4
  ERLANG_DISTRIBUTION_PORTS=$5

  HOST_RECORD="127.0.0.1 ${POD_DNS}"

  # Trap exit so we can try to kill proxies that has stuck in background
  function cleanup {
    set +x
    delete_pattern_in_file "/${HOST_RECORD}/d" /etc/hosts
    log_step "Stopping kubectl proxy."
    kill $! &> /dev/null
  }
  trap cleanup EXIT

  log_step "Stopping local EPMD"
  killall epmd &> /dev/null || true

  log_step "Adding new record to /etc/hosts."
  echo "${HOST_RECORD}" >> /etc/hosts

  log_step "Port forwarding remote Erlang Distribution ports ${ERLANG_DISTRIBUTION_PORTS} ${LOCAL_DIST_PORT} to localhost."
  kubectl port-forward --namespace=${POD_NAMESPACE} \
    ${POD_NAME} \
    ${ERLANG_DISTRIBUTION_PORTS} \
    ${LOCAL_DIST_PORT} \
    &> /dev/null &

  wait_for_ports_to_become_busy ${LOCAL_DIST_PORT}

  return 0
}

# Tests:
# POD_NAME=$(fetch_pod_name talkinto app.kubernetes.io/name=talkinto-web)
# POD_IP=$(get_pod_ip_address talkinto $POD_NAME)
# POD_DNS=$(get_pod_dns_record talkinto $POD_NAME)
# ERLANG_COOKIE=$(get_erlang_cookie talkinto $POD_NAME)
# ensure_port_is_free 5433
# wait_for_ports_to_become_busy 5432
# EPMD_NAMES=$(get_epmd_names talkinto $POD_NAME)
# RELEASE_NAME=$(ger_erlang_release_name_from_epmd_names "${EPMD_NAMES}")
# ERLANG_DISTRIBUTION_PORTS=$(get_erlang_distribution_ports_from_epmd_names "${EPMD_NAMES}")
# POSTGRES_PASSWORD=$(get_postgres_user_password talkinto-staging talkinto)
# get_postgres_connection_url talkinto "${POSTGRES_PASSWORD}" 5432 talkinto


# COMMAND="ktl pg:proxy -n \(.metadata.namespace) -l instance_name=\(.metadata.labels.instance_name) -p5433"
# PADDING="  "
# list_sql_proxy_pods "${COMMAND}" "  "
# list_sql_proxy_users "foo" "  "

# echo "foo"
