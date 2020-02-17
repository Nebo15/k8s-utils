#!/bin/bash
# This script backups all critical data, allowing to move it from one environment to another
K8S_UTILS_DIR="${BASH_SOURCE%/*}"
source ${K8S_UTILS_DIR}/helpers.sh

if [[ "${DOCKER_PASSWORD:-}" == "" ]]; then
  log_step "Creating temporarely Docker Hub token to pull list of container tags."

  DOCKER_USERNAME_AND_PASSWORD=$(jq -r '.auths."https://index.docker.io/v1/".auth' ~/.docker/config.json)
  DOCKER_CREDENTIAL_HELPER=$(jq -r .credsStore ~/.docker/config.json)

  if [[ "${DOCKER_USERNAME_AND_PASSWORD}" != "null" ]]; then
    log_step_append "Resolved Docker Hub login and password from ~/.docker/config.json file"
    DOCKER_USERNAME_AND_PASSWORD=$(echo "${DOCKER_USERNAME_AND_PASSWORD}" | base64 --decode)
    DOCKER_USERNAME_AND_PASSWORD_ARRAY=(${DOCKER_USERNAME_AND_PASSWORD/:/ })
    DOCKER_USERNAME=${DOCKER_USERNAME_AND_PASSWORD_ARRAY[0]}
    DOCKER_PASSWORD=${DOCKER_USERNAME_AND_PASSWORD_ARRAY[1]}
  elif [[ "${DOCKER_CREDENTIAL_HELPER}" != "null" ]]; then
    log_step_append "Fetching Docker Hub password from credentials helper. Only OSX Keychain is currently supported."

    DOCKER_CREDENTIALS=$(docker-credential-${DOCKER_CREDENTIAL_HELPER} list | \
                           jq -r 'to_entries[].key' | \
                           while read; do
                             docker-credential-${DOCKER_CREDENTIAL_HELPER} get <<<"$REPLY";
                           done)
    DOCKER_USERNAME=$(echo "${DOCKER_CREDENTIALS}" | jq -r .Username)
    DOCKER_PASSWORD=$(echo "${DOCKER_CREDENTIALS}" | jq -r .Secret)
  else
    error "Can not automatically resolve Docker Hub password, you set explicitly DOCKER_USERNAME and DOCKER_PASSWORD."
  fi
fi

PROJECT_ROOT_DIR=$(git rev-parse --show-toplevel)
KUBECTL_CONTEXT=$(kubectl config current-context)

function get_cluser_versions() {
  kubectl get deployments \
    --all-namespaces=true \
    --output=json | \
    jq --raw-output '[
      .items[]
      | select(
          .metadata.namespace != "kube-system"
          and .metadata.namespace != "kube-monitoring"
          and .metadata.namespace != "kube-ingress"
          and .metadata.namespace != "kube-ops"
        )
      | {
          app: .metadata.labels."app.kubernetes.io/name",
          version: .spec.template.spec.containers[0].image | split(":")[1],
          container: .spec.template.spec.containers[0].image | split(":")[0],
          ns: .metadata.namespace,
          replicas: .status.replicas,
          available_replicas: .status.availableReplicas
        }
    ]'
}

function get_docker_hub_tags() {
  DOCKER_HUB_TOKEN=$(curl -u${DOCKER_USERNAME}:${DOCKER_PASSWORD} --silent "https://auth.docker.io/token?service=registry.docker.io&scope=repository:$1:pull" | jq -r .token)
  curl -Ss -H "Content-Type: application/json" -H "Authorization: Bearer ${DOCKER_HUB_TOKEN}" "https://registry.hub.docker.com/v2/$1/tags/list?n=100"
}

function get_manifest_version() {
  CHART_NAME=$1
  VALUES_FILE_EXT="${2:-""}.yaml"

  VALUES_PATH="${PROJECT_ROOT_DIR}/rel/deployment/charts/applications/${CHART_NAME}/values${VALUES_FILE_EXT}"
  [[ -e "${VALUES_PATH}" ]] && cat "${VALUES_PATH}" | grep "imageTag" | awk '{print $NF;}' | sed 's/"//g' || echo "Unknown"
}

function prepend_newline() {
  while read line; do echo $line; done;
  echo "" >&2
  echo "" >&2
}

log_step_with_progress "Loading cluster status (this may take a while)"

get_cluser_versions | \
  jq -r '.[] | "\(.ns)|\(.app)|\(.container)|\(.version)|\(.replicas)|\(.available_replicas)"' | \
  while read key
  do
    log_progess_step

    REPO_SLUG=$(echo ${key} | awk -F "|" '{print $3}')
    CURRENT_VERSION=$(echo ${key} | awk -F "|" '{print $4}')
    LATEST_VERSION=$(get_docker_hub_tags "${REPO_SLUG}" "${CURRENT_VERSION}" | jq --raw-output '([.tags[] | scan("[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}")] | max_by(split(".") | (.[0] | tonumber) * 1000000 + (.[1] | tonumber) * 10000 + (.[2] | tonumber)))')
    STAGING_VALUES_VERSION=$(get_manifest_version $(echo ${key} | awk -F "|" '{print $2}') ".staging")
    PRODUCTION_VALUES_VERSION=$(get_manifest_version $(echo ${key} | awk -F "|" '{print $2}') "")

    echo -e ${key}'|'${LATEST_VERSION}'|'${STAGING_VALUES_VERSION}'|'${PRODUCTION_VALUES_VERSION}
  done | \
  prepend_newline | \
  awk \
     -F "|" \
    -v red="$(tput setaf 1)" \
    -v white="$(tput setaf 7)" \
    -v reset="$(tput sgr0)" \
    -v context=${KUBECTL_CONTEXT} \
    'BEGIN {printf "Namespace|App|Image|Latest|Deployed to %s|.staging.yaml|.yaml\n", context} {printf "%s|%s|%s|%s|%s (%s/%s)|%s|%s\n", $1, $2, $3, $7, $4, $6, $5, $8, $9;}' | \
  column -t -s'|'
