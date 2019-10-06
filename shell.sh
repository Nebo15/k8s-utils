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

K8S_NAMESPACE=""
K8S_SELECTOR=
COMMAND=
POD_NAME=

# Read configuration from CLI
while getopts "n:l:p:h" opt; do
  case "$opt" in
    n)  K8S_NAMESPACE=${OPTARG}
        ;;
    l)  K8S_SELECTOR=${OPTARG}
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
shift $(expr $OPTIND - 1 )
COMMAND=$1

if [[ "${COMMAND}" == "" ]]; then
  COMMAND="/bin/sh"
fi

if [[ ! $K8S_SELECTOR && ! $POD_NAME ]]; then
  error "You need to specify Kubernetes selector with '-l' option or pod name via '-p' option."
fi

if [ ! $POD_NAME ]; then
  POD_NAME=$(fetch_pod_name "${POD_NAMESPACE}" "${K8S_SELECTOR}")
fi

if [ ! $POD_NAMESPACE ]; then
  POD_NAMESPACE=$(get_pod_namespace "${POD_NAME}")
fi

lost_step "Running ${COMMAND} on pod ${POD_NAME} in namespace {K8S_NAMESPACE}."
kubectl exec --namespace=${K8S_NAMESPACE} ${POD_NAME} -it -- ${COMMAND}
