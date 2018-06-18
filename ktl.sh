#!/bin/bash
set -e

# Check dependencies
command -v jq >/dev/null 2>&1 || { echo >&2 "jq is not installed. Aborting."; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo >&2 "kubectl is not installed. Aborting."; exit 1; }
command -v gcloud >/dev/null 2>&1 || { echo >&2 "gcloud is not installed. Aborting."; exit 1; }
command -v helm >/dev/null 2>&1 || { echo >&2 "helm is not installed. Aborting."; exit 1; }

CURRENT_DIR="$( cd "$( dirname $( readlink "${BASH_SOURCE[0]}") )" && pwd )"


if [[ "$1" == "shell" ]]; then # WORKS
  OPT=${@#shell}
  ${CURRENT_DIR}/shell.sh ${OPT}
elif [[ "$1" == "erl:shell" ]]; then # WORKS
  OPT=${@#erl:shell}
  ${CURRENT_DIR}/erl-shell.sh ${OPT}
elif [[ "$1" == "iex:observer" ]]; then
  OPT=${@#iex:observer}
  ${CURRENT_DIR}/iex-observer.sh ${OPT}
elif [[ "$1" == "iex:remsh" ]]; then
  OPT=${@#iex:remsh}
  ${CURRENT_DIR}/iex-remsh.sh ${OPT}
elif [[ "$1" == "pg:psql" ]]; then # WORKS
  OPT=${@#pg:psql}
  ${CURRENT_DIR}/pg-psql.sh ${OPT}
elif [[ "$1" == "pg:open" ]]; then # WORKS
  OPT=${@#pg:open}
  ${CURRENT_DIR}/pg-open.sh ${OPT}
elif [[ "$1" == "pg:proxy" ]]; then # WORKS
  OPT=${@#pg:proxy}
  ${CURRENT_DIR}/pg-proxy.sh ${OPT}
elif [[ "$1" == "pg:dump" ]]; then
  OPT=${@#pg:dump}
  ${CURRENT_DIR}/pg-dump.sh ${OPT}
elif [[ "$1" == "pg:restore" ]]; then
  OPT=${@#pg:restore}
  ${CURRENT_DIR}/pg-restore.sh ${OPT}
elif [[ "$1" == "status" ]]; then # WORKS
  OPT=${@#status}
  ${CURRENT_DIR}/status.sh ${OPT}
elif [[ "$1" == "help" ]]; then # WORKS
  ${CURRENT_DIR}/help.sh
elif [[ "$1" == "apply" ]]; then # WORKS
  # We override default behaviour to store update history
  kubectl $@ --record=true
else
  kubectl $@
fi;
