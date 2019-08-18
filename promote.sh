#!/bin/bash
set -em

function show_help {
  echo "
  ktl promote [-f=staging -t=production -a=talkinto-domain]

  Promotes image tag in helm value files taking it from other environment file.

  Warning! This command does not change other Helm configuration which can change from version to version.

  Options:
    -fFROM              Environment name from which the version would be taken. Default: staging.
    -tTO                Environment name in which the version would be updated. Default: production.
    -aAPPLICATION       Application name which should be promoted. By default all applications are promoted.
"
}

FROM="staging"
TO="production"
APPLICATION=""

while getopts "hf:t:a:" opt; do
  case "$opt" in
    f)  FROM="${OPTARG}"
        ;;
    t)  TO="${OPTARG}"
        ;;
    a)  APPLICATION="${OPTARG}"
        ;;
    h)  show_help
        exit 0
        ;;
  esac
done


PROJECT_ROOT_DIR=$(git rev-parse --show-toplevel)
APPLICATIONS_DIR="${PROJECT_ROOT_DIR}/rel/deployment/charts/applications"

function values_path() {
  if [[ "$2" == "production" ]]; then
    echo "${APPLICATIONS_DIR}/$1/values.yaml"
  else
    echo "${APPLICATIONS_DIR}/$1/values.$2.yaml"
  fi
}

function get_manifest_version() {
  VALUES_PATH=$(values_path $1 $2)
  [[ -e "${VALUES_PATH}" ]] && cat "${VALUES_PATH}" | grep "imageTag" | awk '{print $NF;}' | sed 's/"//g' || echo ""
}

function promote() {
  FROM_VERSION=$(get_manifest_version $1 $3)
  TO_VERSION=$(get_manifest_version $1 $2)
  VALUES_PATH=$(values_path $1 $3)

  if [[ "${FROM_VERSION}" != "" && "${TO_VERSION}" != "" ]]; then
    sed -E -i '' 's#(imageTag:[ ]*"[^"]*"[ ]*)#imageTag: "'${TO_VERSION}'"#' "${VALUES_PATH}"
    echo "[I] Promoted $1 ${FROM_VERSION} -> ${TO_VERSION}"
  elif [[ "${FROM_VERSION}" == "" ]]; then
    echo "[W] Skipping $1 app because it have no configuration for $3 environment"
  elif [[ "${TO_VERSION}" == "" ]]; then
    echo "[W] Skipping $1 app because it have no configuration for $2 environment"
  fi;
}

if [[ "${APPLICATION}" == "" ]]; then
  for a in ${APPLICATIONS_DIR}/*/ ; do
    APPLICATION=$(basename "$a")
    promote $APPLICATION $FROM $TO
  done
else
  if [[ ! -d "${APPLICATIONS_DIR}/${APPLICATION}" ]]; then
    echo "[E] Application ${APPLICATION} does not exist"
    exit 1
  fi;

  promote $APPLICATION $FROM $TO
fi;
