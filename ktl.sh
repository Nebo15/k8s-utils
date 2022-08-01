#!/bin/bash
set -e

# Check dependencies
command -v jq >/dev/null 2>&1 || { echo >&2 "jq is not installed. Aborting."; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo >&2 "kubectl is not installed. Aborting."; exit 1; }
command -v gke-gcloud-auth-plugin --version >/dev/null 2>&1 || { echo >&2 "gke-gcloud-auth-plugin is not installed. Use 'gcloud components install gke-gcloud-auth-plugin'. Aborting."; exit 1; }

CURRENT_DIR="$( cd "$( dirname $( readlink "${BASH_SOURCE[0]}") )" && pwd )"

if [[ "$1" == "shell" ]]; then
  OPTIND=2
  source ${CURRENT_DIR}/shell.sh
elif [[ "$1" == "erl:shell" ]]; then
  OPTIND=2
  source ${CURRENT_DIR}/erl-shell.sh
elif [[ "$1" == "iex:shell" ]]; then
  OPTIND=2
  source ${CURRENT_DIR}/iex-shell.sh
elif [[ "$1" == "iex:observer" ]]; then
  OPTIND=2
  source ${CURRENT_DIR}/iex-observer.sh
elif [[ "$1" == "iex:remsh" ]]; then
  OPTIND=2
  source ${CURRENT_DIR}/iex-remsh.sh
elif [[ "$1" == "pg:psql" ]]; then
  OPTIND=2
  source ${CURRENT_DIR}/pg-psql.sh
elif [[ "$1" == "pg:open" ]]; then
  OPTIND=2
  source ${CURRENT_DIR}/pg-open.sh
elif [[ "$1" == "pg:proxy" ]]; then
  OPTIND=2
  source ${CURRENT_DIR}/pg-proxy.sh
elif [[ "$1" == "pg:ps" ]]; then
  OPTIND=2
  source ${CURRENT_DIR}/pg-ps.sh
elif [[ "$1" == "pg:kill" ]]; then
  OPTIND=2
  source ${CURRENT_DIR}/pg-kill.sh
elif [[ "$1" == "pg:outliers" ]]; then
  OPTIND=2
  source ${CURRENT_DIR}/pg-outliers.sh
elif [[ "$1" == "pg:diagnose" ]]; then
  OPTIND=2
  source ${CURRENT_DIR}/pg-diagnose.sh
elif [[ "$1" == "pg:dump" ]]; then
  OPTIND=2
  source ${CURRENT_DIR}/pg-dump.sh
elif [[ "$1" == "pg:restore" ]]; then
  OPTIND=2
  source ${CURRENT_DIR}/pg-restore.sh
elif [[ "$1" == "pg:copy" ]]; then
  OPTIND=2
  source ${CURRENT_DIR}/pg-copy.sh
elif [[ "$1" == "status" ]]; then
  OPTIND=2
  source ${CURRENT_DIR}/status.sh
elif [[ "$1" == "promote" ]]; then
  OPTIND=2
  source ${CURRENT_DIR}/promote.sh
elif [[ "$1" == "help" ]]; then
  OPTIND=2
  source ${CURRENT_DIR}/help.sh
elif [[ "$1" == "apply" ]]; then
  # We override default behaviour to store update history
  kubectl $@ --record=true
else
  kubectl $@
fi;
