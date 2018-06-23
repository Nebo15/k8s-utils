#!/bin/bash
# This script backups all critical data, allowing to move it from one environment to another
echo "Creating temporarely Docker Hub token to pull list of tags"
DOCKER_REGISTRY="https://index.docker.io/v1/"
DOCKER_CREDENTIALS=$(echo "${DOCKER_REGISTRY}" | docker-credential-osxkeychain get)
DOCKER_USERNAME=$(echo "${DOCKER_CREDENTIALS}" | jq -r .Username)
DOCKER_PASSWORD=$(echo "${DOCKER_CREDENTIALS}" | jq -r .Secret)
PROJECT_ROOT_DIR=$(git rev-parse --show-toplevel)
KUBECTL_CONTEXT=$(kubectl config current-context)

function get_cluser_versions() {
  kubectl get deployments \
    --all-namespaces=true \
    --output=json | \
    jq --raw-output '[
      .items[] | select( .metadata.namespace != "kube-system" and .metadata.namespace != "monitoring" and .metadata.labels.app != "db" ) | { app: .metadata.labels.app, version: .spec.template.spec.containers[0].image | split(":")[1], container: .spec.template.spec.containers[0].image | split(":")[0], ns: .metadata.namespace }
    ]'
}

function get_docker_hub_tags() {
  DOCKER_HUB_TOKEN=$(curl -u${DOCKER_USERNAME}:${DOCKER_PASSWORD} --silent "https://auth.docker.io/token?service=registry.docker.io&scope=repository:$1:pull" | jq -r .token)
  curl -Ss -H "Content-Type: application/json" -H "Authorization: Bearer ${DOCKER_HUB_TOKEN}" "https://registry.hub.docker.com/v2/$1/tags/list?n=100"
}

function get_manifest_version() {
  VALUES_PATH="${PROJECT_ROOT_DIR}/rel/deployment/charts/$1/values.$2.yaml"
  [[ -e "${VALUES_PATH}" ]] && cat "${VALUES_PATH}" | grep "imageTag" | awk '{print $NF;}' | sed 's/"//g' || echo "Unknown"
}

echo "Loading cluster status (this may take a while).."

get_cluser_versions | \
  jq -r '.[] | "\(.ns)|\(.app)|\(.container)|\(.version)"' | \
  while read key
  do
    REPO_SLUG=$(echo ${key} | awk -F "|" '{print $3}')
    CURRENT_VERSION=$(echo ${key} | awk -F "|" '{print $4}')
    LATEST_VERSION=$(get_docker_hub_tags "${REPO_SLUG}" "${CURRENT_VERSION}" | jq --raw-output '([.tags[] | scan("[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}")] | max_by(split(".") | (.[0] | tonumber) * 1000000 + (.[1] | tonumber) * 10000 + (.[2] | tonumber)))')
    STAGING_VALUES_VERSION=$(get_manifest_version $(echo ${key} | awk -F "|" '{print $2}') "staging")
    PRODUCTION_VALUES_VERSION=$(get_manifest_version $(echo ${key} | awk -F "|" '{print $2}') "production")

    echo -e ${key}'|'${LATEST_VERSION}'|'${STAGING_VALUES_VERSION}'|'${PRODUCTION_VALUES_VERSION}
  done | \
  awk \
     -F "|" \
    -v red="$(tput setaf 1)" \
    -v white="$(tput setaf 7)" \
    -v reset="$(tput sgr0)" \
    -v context=${KUBECTL_CONTEXT} \
    'BEGIN {printf "Namespace|App|Image|Vsn on %s|Latest vsn|Defined for staging|for production\n", context} {printf "%s|%s|%s|%s|%s|%s|%s\n", $1, $2, $3, $4, $5, $6, $7;}' | \
  column -t -s'|'
