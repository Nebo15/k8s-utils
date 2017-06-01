#!/bin/bash
# This script backups all critical data, allowing to move it from one environment to another

function get_cluser_versions() {
  kubectl get pods --all-namespaces=true --output=json | \
    jq --raw-output '[ .items[] | select( .metadata.namespace != "" and .metadata.namespace != "kube-system" and .metadata.namespace != "monitoring" and .metadata.labels.app != "postgresql" ) | { app: .metadata.labels.app, version: .metadata.labels.version, pod_name: .metadata.name, container: .spec.containers[0].image | split(":")[0], ns: .metadata.namespace } ]'
}

function get_docker_hub_token() {
  curl --silent "https://auth.docker.io/token?service=registry.docker.io&scope=$1" | jq -r .token
}

function get_version_on_k8s_local() {
  CONFIG_PATH="./clusters/api/$1/api/dep.yaml"
  ruby -ryaml -e "puts YAML.load(File.read('$path'))['metadata']['labels']['version']"
}


CLUSTER_VERSIONS=$(get_cluser_versions)

# Get token to be able to talk to Docker Hub
DOCKER_HUB_SCOPES=$(echo ${CLUSTER_VERSIONS} | jq 'map(.container) | "repository%3A" + join("%3Apull+repository%3A") + "%3Apull"')
# DOCKER_HUB_SCOPES=${DOCKER_HUB_SCOPES//\//%2F}

# "Application\tContainer\tDeployed version\tPod Name\n"$1}'
get_cluser_versions | \
  jq -r '.[] | "\(.app)\t\(.container)\t\(.version)\t\(.pod_name)" ' | \
  column -t

while read key
do
  curl -Ss "$RIAK/buckets/$BUCKET/keys/$key?keys"
done


# DOCKER_HUB_TOKEN=$(get_docker_hub_token repository:nebo15/man_api:pull)
# curl -H "Content-Type: application/json" -H "Authorization: Bearer ${DOCKER_HUB_TOKEN}" https://registry.hub.docker.com/v2/nebo15/man_api/tags/list -v # &last=last_tag




# LS: kubectl get pods --sort-by='.status.containerStatuses[0].restartCount'



