#!/bin/bash
command -v kubectl >/dev/null 2>&1 || { echo >&2 "kubectl is not installed. Aborting."; exit 1; }
command -v gcloud >/dev/null 2>&1 || { echo >&2 "gcloud is not installed. Aborting."; exit 1; }

KUBECTL_CONTEXT=$(echo `kubectl config current-context` | cut -d '_' -f 4)
GCLOUD_CONTEXT=$(gcloud config list --format 'value(core.project)' 2>/dev/null)
GIT_BRANCH=$(git branch | grep \* | cut -d ' ' -f2)

function check_cluster_name()
{
  if [[ "${KUBECTL_CONTEXT}" != *"${GIT_BRANCH}"* && "$@" != *"config"*"context"* ]]; then
    read -p "Cluster name do not match git branch name! Are you sure? [Y/n] " -n 1 -r
    echo
    if ! [[ $REPLY =~ ^[Yy]$ ]]; then
      exit 1
    fi
  fi;
}

check_cluster_name

if [[ "$1" == "shell" ]]; then
  OPT=${@#shell}
  /www/k8s/bin/shell.sh ${OPT}
elif [[ "$1" == "connect" ]]; then
  OPT=${@#connect}
  /www/k8s/bin/pg-connect.sh ${OPT}
elif [[ "$1" == "observe" ]]; then
  OPT=${@#observe}
  /www/k8s/bin/erl-observe.sh ${OPT}
elif [[ "$1" == "apply" ]]; then
  kubectl $@ --record=true
else
  kubectl $@
fi;

