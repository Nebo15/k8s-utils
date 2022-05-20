#!/bin/bash
K8S_UTILS_DIR="${BASH_SOURCE%/*}"
source ${K8S_UTILS_DIR}/helpers.sh

function show_help {
  echo "
  ktl promote [-f=staging -t=production -a=talkinto-domain]

  Promotes image tag in terraform's versions.auto.tfvars value files taking it from other environment file.

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

TERRAFORM_DIR="${PROJECT_ROOT_DIR}/rel/deployment/terraform/environments"

function versions_path() {
  echo "${TERRAFORM_DIR}/$1/versions.auto.tfvars"
}

function get_version() {
  VERSIONS_PATH=$(versions_path $2)
  [[ -e "${VERSIONS_PATH}" ]] && cat "${VERSIONS_PATH}" | grep "$1_image_tag" | awk '{print $NF;}' | sed 's/"//g' || echo ""
}

function commit_changes() {
  local APPLICATION=$1
  local FROM=$2
  local FROM_VERSION=$3
  local TO=$4
  local TO_VERSION=$5
  local VERSIONS_PATH=$6

  git add ${VERSIONS_PATH}
  git commit \
    -m "Promote ${TO}/${APPLICATION} from ${FROM_VERSION} to ${TO_VERSION} [ci skip]" \
    -m "Promoted from ${FROM} to ${TO} environment." \
    &> /dev/null
}

function log_changelog() {
  APPLICATION=$1
  FROM_VERSION=$2

  set +eo pipefail
  MIX_CHANGELOG=$(cd ${PROJECT_ROOT_DIR} && mix rel.changelog --from-version ${FROM_VERSION} --application ${APPLICATION} 2>&1 | sed '/^\s*$/d')
  set -eo pipefail

  log_step_append ""
  log_step_append "${MIX_CHANGELOG}"
  log_step_append ""
}

function promote() {
  local APPLICATION=$1
  local FROM=$2
  local TO=$3
  local DRY=$4
  local FROM_VERSION=$(get_version $APPLICATION $TO)
  local TO_VERSION=$(get_version $APPLICATION $FROM)
  local VERSIONS_PATH=$(versions_path $TO)

  echo "APPLICATION: ${APPLICATION}"

  if [[ "${FROM_VERSION}" != "" && "${TO_VERSION}" != "" ]]; then
    if [[ "${FROM_VERSION}" != "${TO_VERSION}" ]]; then
      GIT_CHANGES=$(git status --porcelain ${VERSIONS_PATH})
      if [[ ${GIT_CHANGES} ]]; then
        error "${VERSIONS_PATH} has changes in the git working tree, commit or stash all the changes before promoting"
      elif [[ "${DRY}" == "dry" ]]; then
        log_step "Going to promote ${APPLICATION} ${FROM_VERSION} -> ${TO_VERSION}"
        log_changelog ${APPLICATION} ${FROM_VERSION}
      else
        replace_pattern_in_file 's#('${APPLICATION}'_image_tag[ ]*=[ ]*"[^"]*"[ ]*)#'${APPLICATION}'_image_tag = "'${TO_VERSION}'"#' "${VERSIONS_PATH}"
        commit_changes ${APPLICATION} ${FROM} ${FROM_VERSION} ${TO} ${TO_VERSION} ${VERSIONS_PATH}
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

function list_all_applications() {
  local VERSIONS_PATH=$(versions_path $1)
  [[ -e "${VERSIONS_PATH}" ]] && cat "${VERSIONS_PATH}" | grep "image_tag" | awk '{print $1;}' | sed 's/_image_tag//g'
}

function promote_all() {
  local TERRAFORM_DIR=$1
  local APPLICATION=$2
  local FROM=$3
  local TO=$4
  local DRY=${5:-"clean"}

  APPLICATION=${APPLICATION//-/_}

  if [[ "${APPLICATION}" == "" ]]; then
    for a in $(list_all_applications $FROM) ; do
      APPLICATION=$(basename "$a")
      promote $APPLICATION $FROM $TO $DRY
    done
  else
    if [[ $(get_version $APPLICATION $FROM) == "" ]]; then
      error "Application ${APPLICATION} does not exist"
    fi;

    promote $APPLICATION $FROM $TO $DRY
  fi;
}

if [[ $(git diff --name-only --cached | wc -l) -gt 0 ]]; then
  error "You have staged changes, please commit or stash them first"
fi

git pull origin $(git branch --show-current) &> /dev/null
git fetch --tags --force &> /dev/null

promote_all "${TERRAFORM_DIR}" "${APPLICATION}" "${FROM}" "${TO}" "dry"

read -p "[?] Promote and commit all changes? (Yy/Nn)" -n 1 -r
echo    # (optional) move to a new line
if [[ $REPLY =~ ^[Yy]$ ]]
then
  banner "Promoting and commiting changes"
  promote_all "${TERRAFORM_DIR}" "${APPLICATION}" "${FROM}" "${TO}"
else
  log_step "Cancelled, got ${REPLY}"
fi
