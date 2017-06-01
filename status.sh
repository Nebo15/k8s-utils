#!/bin/bash
# This script backups all critical data, allowing to move it from one environment to another

function get_cluser_versions() {
  kubectl get pods --all-namespaces=true --output=json | \
    jq --raw-output '[ .items[] | select( .metadata.namespace != "" and .metadata.namespace != "kube-system" and .metadata.namespace != "monitoring" and .metadata.labels.app != "postgresql" ) | { app: .metadata.labels.app, version: .metadata.labels.version, pod_name: .metadata.name, container: .spec.containers[0].image | split(":")[0], ns: .metadata.namespace } ]'
}

function get_docker_hub_tags() {
  TOKEN=$(curl --silent "https://auth.docker.io/token?service=registry.docker.io&scope=repository:$1:pull" | jq -r .token)
  curl -Ss -H "Content-Type: application/json" -H "Authorization: Bearer ${TOKEN}" "https://registry.hub.docker.com/v2/$1/tags/list?n=100"
}

function get_version_on_k8s_local() {
  CONFIG_PATH="./clusters/api/$1/api/dep.yaml"
  ruby -ryaml -e "puts YAML.load(File.read('$path'))['metadata']['labels']['version']"
}

echo "Loading cluster status (this may take a while).."

# "Application\tContainer\tDeployed version\tPod Name\n"$1}'
get_cluser_versions | \
  jq -r '.[] | "\(.app)\t\(.container)\t\(.version)\t\(.pod_name)"' | \
  while read key
  do
    REPO_SLUG=$(echo ${key} | awk '{print $2}')
    CURRENT_VERSION=$(echo ${key} | awk '{print $3}')
    LATEST_VERSION=$(get_docker_hub_tags "${REPO_SLUG}" "${CURRENT_VERSION}" | jq --raw-output '([.tags[] | scan("[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}")] | max_by(split(".") | (.[0] | tonumber) * 1000000 + (.[1] | tonumber) * 10000 + (.[2] | tonumber)))')

    # echo -n "." >&2
    echo -e ${key}'\t'${LATEST_VERSION}
  done | \
  awk -v red="$(tput setaf 1)" -v white="$(tput setaf 7)" -v reset="$(tput sgr0)" 'BEGIN {printf "%sApp%s\t%sImage%s\t%sDeployed_version%s\t%sLatest_version%s\t%sPod_name%s\n", white, reset, white, reset, white, reset, white, reset, white, reset} {if ($3 != $5) color=red; else color=white; printf "%s%s%s\t%s%s%s\t%s%s%s\t%s%s%s\t%s%s%s\n", white, $1, reset, white, $2, reset, color, $3, reset, white, $5, reset, white, $4, reset;}' | \
  column -t




