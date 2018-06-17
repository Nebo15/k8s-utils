#!/bin/bash
set -e

# Check dependencies
command -v jq >/dev/null 2>&1 || { echo >&2 "jq is not installed. Aborting."; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo >&2 "kubectl is not installed. Aborting."; exit 1; }
command -v gcloud >/dev/null 2>&1 || { echo >&2 "gcloud is not installed. Aborting."; exit 1; }
command -v helm >/dev/null 2>&1 || { echo >&2 "helm is not installed. Aborting."; exit 1; }

CURRENT_DIR="$( cd "$( dirname $( readlink "${BASH_SOURCE[0]}") )" && pwd )"

# KUBECTL_CONTEXT=$(echo `kubectl config current-context` | cut -d '_' -f 4)
# GCLOUD_CONTEXT=$(gcloud config list --format 'value(core.project)' 2>/dev/null)
# GIT_BRANCH=$(git branch | grep \* | cut -d ' ' -f2)
#
# function check_cluster_and_project_name()
# {
#   if [[ "${KUBECTL_CONTEXT}" != *"${GIT_BRANCH}"* && "$@" != *"config"*"context"* ]]; then
#     read -p "Cluster name do not match git branch name! Are you sure? [Y/n] " -n 1 -r
#     echo
#     if ! [[ $REPLY =~ ^[Yy]$ ]]; then
#       exit 1
#     fi
#   fi;
# }
#
# check_cluster_and_project_name

if [[ "$1" == "shell" ]]; then # WORKS
  OPT=${@#shell}
  ${CURRENT_DIR}/shell.sh ${OPT}
elif [[ "$1" == "pg:psql" ]]; then
  OPT=${@#pg:psql}
  ${CURRENT_DIR}/pg-psql.sh ${OPT}
elif [[ "$1" == "pg:proxy" ]]; then
  OPT=${@#pg:proxy}
  ${CURRENT_DIR}/pg-proxy.sh ${OPT}
elif [[ "$1" == "erl:shell" ]]; then # WORKS
  OPT=${@#erl:shell}
  ${CURRENT_DIR}/erl-shell.sh ${OPT}
elif [[ "$1" == "iex:observer" ]]; then
  OPT=${@#iex:observer}
  ${CURRENT_DIR}/iex-observer.sh ${OPT}
elif [[ "$1" == "iex:remsh" ]]; then
  OPT=${@#iex:remsh}
  ${CURRENT_DIR}/iex-remsh.sh ${OPT}
elif [[ "$1" == "pg:dump" ]]; then
  OPT=${@#dump}
  ${CURRENT_DIR}/pg-dump.sh ${OPT} -d
elif [[ "$1" == "pg:restore" ]]; then
  OPT=${@#restore}
  ${CURRENT_DIR}/pg-backup.sh ${OPT} -r
elif [[ "$1" == "status" ]]; then
  OPT=${@#status}
  ${CURRENT_DIR}/status.sh ${OPT}
elif [[ "$1" == "help" ]]; then
  ${CURRENT_DIR}/help.sh
elif [[ "$1" == "apply" ]]; then
  # We override default behaviour to store update history
  kubectl $@ --record=true
else
  kubectl $@
fi;
