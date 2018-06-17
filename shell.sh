#!/bin/bash
set -e

function show_help {
  echo "
  ktl shell -lSELECTOR [-nNAMESPACE -h /bin/sh]

  Connects to the shell of a random pod selected by label and namespace.

  By default it runs /bin/sh.

  Examples:
    ktl shell -lapp=hammer-web               Connect to one of the pods of hammer-web application in default namespace.
    ktl shell -lapp=hammer-web -nweb         Connect to one of the pods of hammer-web application in web namespace.
    ktl shell -lapp=hammer-web /bin/bash     Connect to one of the pods of hammer-web application and run /bin/bash.
"
}

K8S_NAMESPACE=""

# Read configuration from CLI
while getopts "n:l:h" opt; do
  case "$opt" in
    n)  K8S_NAMESPACE="--namespace=${OPTARG}"
        ;;
    l)  K8S_SELECTOR=${OPTARG}
        ;;
    c)  COMMAND=${OPTARG}
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

# Required part of config
if [ ! $K8S_SELECTOR ]; then
  echo "[E] You need to specify Kubernetes selector with '-l' option."
  exit 1
fi

POD_NAME=$(
  kubectl get pods ${K8S_NAMESPACE} \
    -l ${K8S_SELECTOR} \
    -o jsonpath='{.items[0].metadata.name}' \
    --field-selector=status.phase=Running
)

if [[ "${POD_NAME}" == "" ]]; then
  echo "[E] Pod wasn't found. Try to select it with -n [namespace] and -l [selector] options."
  exit 1
fi

echo "Found pod ${POD_NAME}."
kubectl exec ${K8S_NAMESPACE} ${POD_NAME} -it -- ${COMMAND}
