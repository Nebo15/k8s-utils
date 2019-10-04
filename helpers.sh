#!/bin/bash
set -meuo pipefail

log() {
  echo "- $1" >&2
}

banner() {
  echo ""
  echo "  $1"
  echo ""
}

error() {
  echo "[E] $1" >&2
  exit 1
}

PROJECT_ROOT_DIR=$(git rev-parse --show-toplevel)
HELM_APPLICATION_CHARTS_DIR="${PROJECT_ROOT_DIR}/rel/deployment/charts/applications"

function fetch_pod_name() {
  NAMESPACE=$1
  SELECTOR=$2

  log "Selecting pod with '--namespace=${NAMESPACE} --selector=${SELECTOR}' options."

  POD_NAME=$(
    kubectl get pods --namespace="${NAMESPACE}" \
      --selector="${SELECTOR}" \
      --field-selector='status.phase=Running' \
      --output="json" \
      | jq -r '.items[0].metadata.name'
    )

  if [[ "${POD_NAME}" == "" || "${POD_NAME}" == "null" ]]; then
    error "Pod not found. Use -h for list of available selector options."
  else
    echo "${POD_NAME}"
  fi
}

# Pods

function get_pod_ip_address() {
  NAMESPACE=$1
  POD_NAME=$2

  log "Getting pod ${POD_NAME} cluster IP address"

  kubectl get pod ${POD_NAME} --namespace="${NAMESPACE}" --output="json" \
    | jq -r '.status.podIP'
}

function get_pod_dns_record() {
  NAMESPACE=$1
  POD_NAME=$2

  POD_IP=$(get_pod_ip_address "${NAMESPACE}" "${POD_NAME}")
  echo $(echo "${POD_IP}" | sed 's/\./-/g')."${POD_NAME}.pod.cluster.local"
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

function wait_for_ports_to_become_busy() {
  PORT=$1

  log "Waiting for for ports ${PORT} to start responding"

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

  log "Resolving PostgreSQL ${POSTGRES_USER} user password for Cloud SQL instance ${SQL_INSTANCE_NAME}"

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
    log "Stopping port forwarding."
    kill $! &> /dev/null
    kill %1 &> /dev/null
  }
  trap cleanup EXIT

  log "Port forwarding remote PostgreSQL to localhost port ${PORT}."
  kubectl --namespace="${PROXY_POD_NAMESPACE}" port-forward ${PROXY_POD_NAME} ${PORT}:5432 &> /dev/null &

  wait_for_ports_to_become_busy ${PORT}

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
