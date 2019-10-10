#!/bin/bash
K8S_UTILS_DIR="${BASH_SOURCE%/*}"
source ${K8S_UTILS_DIR}/helpers.sh

function show_help {
  echo "
  ktl shell -lSELECTOR or -pPOD_NAME [-nNAMESPACE -h] [/bin/sh]

  Connects to the shell of a random pod selected by label and namespace.

  By default it runs /bin/sh.

  Examples:
    ktl shell -lapp=hammer-web               Connect to one of the pods of hammer-web application in default namespace.
    ktl shell -lapp=hammer-web -nweb         Connect to one of the pods of hammer-web application in web namespace.
    ktl shell -lapp=hammer-web /bin/bash     Connect to one of the pods of hammer-web application and run /bin/bash.
"
}

POD_NAMESPACE=""
POD_SELECTOR=
COMMAND="/bin/sh"
POD_NAME=

# Read configuration from CLI
while getopts "n:l:p:h" opt; do
  case "$opt" in
    n)  POD_NAMESPACE=${OPTARG}
        ;;
    l)  POD_SELECTOR=${OPTARG}
        ;;
    c)  COMMAND=${OPTARG}
        ;;
    p)  POD_NAME=${OPTARG}
        ;;
    h)  show_help
        exit 0
        ;;
  esac
done
shift $(expr $OPTIND - 1)
REST_COMMAND=$@

if [[ "${REST_COMMAND}" != "" ]]; then
  COMMAND="${REST_COMMAND}"
fi

if [[ ! $POD_SELECTOR && ! $POD_NAME ]]; then
  error "You need to specify Kubernetes selector with '-l' option or pod name via '-p' option."
fi

if [ ! $POD_NAME ]; then
  POD_NAME=$(fetch_pod_name "${POD_NAMESPACE}" "${POD_SELECTOR}")
fi

if [ ! $POD_NAMESPACE ]; then
  POD_NAMESPACE=$(get_pod_namespace "${POD_NAME}")
fi

log_step "Running ${COMMAND} on pod ${POD_NAME} in namespace ${POD_NAMESPACE}."
kubectl exec --namespace=${POD_NAMESPACE} ${POD_NAME} -it -- ${COMMAND}
