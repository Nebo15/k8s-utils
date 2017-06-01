#!/bin/bash
# This script backups all critical data, allowing to move it from one environment to another

function get_cluser_versions() {
  kubectl get pods --all-namespaces=true --output=json | \
    jq --raw-output '[ .items[] | select( .metadata.namespace != "" and .metadata.namespace != "kube-system" and .metadata.namespace != "monitoring" and .metadata.labels.app != "postgresql" ) | { app: .metadata.labels.app, version: .metadata.labels.version, pod_name: .metadata.name, container: .spec.containers[0].image | split(":")[0], ns: .metadata.namespace } ]'
}

get_cluser_versions # | jq -r '.[] | "\(.app)\t\(.version)"'


# LS: kubectl get pods --sort-by='.status.containerStatuses[0].restartCount'


