#!/bin/bash
K8S_UTILS_DIR="${BASH_SOURCE%/*}"
source ${K8S_UTILS_DIR}/helpers.sh

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

APPLICATIONS_DIR="${PROJECT_ROOT_DIR}/rel/deployment/charts/applications"

function values_path() {
  if [[ "$2" == "production" ]]; then
    echo "${APPLICATIONS_DIR}/$1/values.yaml"
  else
    echo "${APPLICATIONS_DIR}/$1/values.$2.yaml"
  fi
}

function get_helm_version() {
  VALUES_PATH=$(values_path $1 $2)
  [[ -e "${VALUES_PATH}" ]] && cat "${VALUES_PATH}" | grep "imageTag" | awk '{print $NF;}' | sed 's/"//g' || echo ""
}

function commit_changes() {
  local APPLICATION=$1
  local FROM=$2
  local FROM_VERSION=$3
  local TO=$4
  local TO_VERSION=$5
  local VALUES_PATH=$6

  git add ${VALUES_PATH}
  git commit \
    -m "Promote ${TO}/${APPLICATION} from ${FROM_VERSION} to ${TO_VERSION} [ci skip]" \
    -m "Promoted from ${FROM} to ${TO} environment." \
    &> /dev/null
}

function promote() {
  local APPLICATION=$1
  local FROM=$2
  local TO=$3
  local DRY=$4
  local FROM_VERSION=$(get_helm_version $APPLICATION $TO)
  local TO_VERSION=$(get_helm_version $APPLICATION $FROM)
  local VALUES_PATH=$(values_path $APPLICATION $TO)

  if [[ "${FROM_VERSION}" != "" && "${TO_VERSION}" != "" ]]; then
    if [[ "${FROM_VERSION}" != "${TO_VERSION}" ]]; then
      GIT_CHANGES=$(git status --porcelain ${VALUES_PATH})
      if [[ ${GIT_CHANGES} ]]; then
        error "${VALUES_PATH} has changes in the git working tree, commit or stash all the changes before promoting"
      elif [[ "${DRY}" == "dry" ]]; then
        log_step "Going to promote ${APPLICATION} ${FROM_VERSION} -> ${TO_VERSION}"
      else
        replace_pattern_in_file 's#(imageTag:[ ]*"[^"]*"[ ]*)#imageTag: "'${TO_VERSION}'"#' "${VALUES_PATH}"
        commit_changes ${APPLICATION} ${FROM} ${FROM_VERSION} ${TO} ${TO_VERSION} ${VALUES_PATH}
        log_step "Promoted ${APPLICATION} ${FROM_VERSION} -> ${TO_VERSION}"
      fi
    else
      log_step "Skipping ${APPLICATION} because there are no version changes compared to ${TO} environment"
    fi
  elif [[ "${FROM_VERSION}" == "" ]]; then
    warning "Skipping ${APPLICATION} app because it have no configuration for ${FROM} environment"
  elif [[ "${TO_VERSION}" == "" ]]; then
    warning "Skipping ${APPLICATION} app because it have no configuration for ${TO} environment"
  fi;
}

function promote_all() {
  local APPLICATIONS_DIR=$1
  local APPLICATION=$2
  local FROM=$3
  local TO=$4
  local DRY=${5:-"clean"}

  if [[ "${APPLICATION}" == "" ]]; then
    for a in ${APPLICATIONS_DIR}/*/ ; do
      APPLICATION=$(basename "$a")
      promote $APPLICATION $FROM $TO $DRY
    done
  else
    if [[ ! -d "${APPLICATIONS_DIR}/${APPLICATION}" ]]; then
      error "Application ${APPLICATION} does not exist"
    fi;

    promote $APPLICATION $FROM $TO $DRY
  fi;
}

if [[ $(git diff --name-only --cached | wc -l) -gt 0 ]]; then
  error "You have staged changes, "
fi

promote_all "${APPLICATIONS_DIR}" "${APPLICATION}" "${FROM}" "${TO}" "dry"

read -p "[?] Promote and commit all changes? (Yy/Nn)" -n 1 -r
echo    # (optional) move to a new line
if [[ $REPLY =~ ^[Yy]$ ]]
then
  banner "Promoting and commiting changes"
  promote_all "${APPLICATIONS_DIR}" "${APPLICATION}" "${FROM}" "${TO}"
else
  log_step "Cancelled, got ${REPLY}"
fi
