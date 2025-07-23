#!/bin/bash

VERSION="0.1.20250723018"

outputPrefix() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S.%N %Z')]"
}

echoPrefix() {
  echo "$(outputPrefix) ${SCRIPT_NAME}:"
}

echoWithoutPrefix() {
  echo "${@}"
}

# An echo with a prefix that has a timestamp, script name, etc.
# Output is also printed to ${TEE_FILE} in the collection
echoInfo() {
  echo "$(echoPrefix) ${@}"
}

# Same as echoInfo but only does anything if the log level is greater than 1
echoVerbose() {
  if [ ${OPTIONS[log]} -gt 1 ]; then
    echoInfo "${@}"
  fi
}

# Same as echoInfo but only does anything if the log level is greater than or equal to 3
echoVerbose3() {
  if [ ${OPTIONS[log]} -gt 1 ]; then
    echoInfo "${@}"
  fi
}

# Same as echoInfo but only does anything if the log level is greater than or equal to 3
echoVerbose4() {
  if [ ${OPTIONS[log]} -gt 1 ]; then
    echoInfo "${@}"
  fi
}

# Same as echoInfo but only does anything if the log level is greater than or equal to 3
echoVerbose5() {
  if [ ${OPTIONS[log]} -gt 1 ]; then
    echoInfo "${@}"
  fi
}

# Writes directly to ${TEE_FILE} in the collection rather than stdout because
# we've seen large writes cause issues with oc adm must-gather somtimes.
echoLarge() {
  echo "$(echoPrefix) ${@}" >> "${TEE_FILE}"
}

# Same as echoLarge but only does anything if the log level is greater than 1
echoLargeVerbose() {
  if [ ${OPTIONS[log]} -gt 1 ]; then
    echoLarge "${@}"
  fi
}

startRun() {
  echoInfo "Started $(basename "${0}")"
}

endRun() {
  echoInfo "Finished $(basename "${0}")"

  # force disk flush to ensure that all data gathered is accessible in the copy container
  sync

  echoInfo "sync finished"
}

ensureAllPodsJSON() {
  if [ "${ALL_PODS_JSON}" = "" ]; then
    ALL_PODS_JSON="$(oc get pods -A -o json)"

    # This is too heavy and causes issues with oc
    echoLargeVerbose "ALL_PODS_JSON = ${ALL_PODS_JSON}"
  fi
}

getPodLogs() {
  ns="${1}"
  pod="${2}"

  # TODO could we re-use ${ALL_PODS_JSON} for this?
  containers=$(oc get pod "$pod" -n "$ns" -o jsonpath='{.spec.containers[*].name}')

  for container in $containers; do
    echoInfo "Collecting pod logs for $ns/$pod [$container]"

    # The main oc adm inspect for all namespaces creates a directory structure like:
    # 
    # ├── namespaces
    # │   ├── simple
    # │   │   └── core
    # │   │       └── pods
    # │   │           ├── $POD.yaml
    #
    # However, oc adm inspect on a namespace with pod logs doesn't have the `core` folder:
    # 
    # ├── namespaces
    # │   └── simple
    # │       ├── pods
    # │       │   ├── $POD
    # │       │   │   ├── $POD.yaml
    # │       │   │   └── $CONTAINER
    # │       │   │       └── $CONTAINER
    # │       │   │           └── logs
    # │       │   │               ├── current.log
    # │       │   │               └── previous.log
    # 
    # So mimic this structure:
    OUTDIR="${MGOUTPUT}/namespaces/${ns}/pods/${pod}/${container}/${container}/logs/"
    mkdir -p "${OUTDIR}"

    # Also copy in the YAML
    oc get pod -o yaml -n "${ns}" "${pod}" > "${MGOUTPUT}/namespaces/${ns}/pods/${pod}/${pod}.yaml" &
    pids+=($!)

    echoVerbose "Sparked off oc get pod ${ns}/${pod}; PIDs = ${pids[@]}"

    oc logs --timestamps "$pod" -c "$container" -n "$ns" > "${OUTDIR}/current.log"
    oc logs --timestamps "$pod" -c "$container" --previous -n "$ns" > "${OUTDIR}/previous.log"
  done
}

getPodLogsByAppName() {
  SEARCH="${1}"
  echoInfo "Started getPodLogsByAppName for ${SEARCH}"
  ensureAllPodsJSON
  INPUT="$(echo "${ALL_PODS_JSON}" | jq -r ".items[] | select(.metadata.labels.app == \"${SEARCH}\") | [.metadata.namespace, .metadata.name] | @tsv")"
  echoVerbose "Pods = ${INPUT}"
  if [ "${INPUT}" != "" ]; then
    while IFS=$'\t' read -r ns pod; do
      getPodLogs "${ns}" "${pod}"
    done <<< "${INPUT}" # Piping into the while loop would be a subshell and would lose any variable updates (e.g. pids)
  fi
  echoInfo "Finished getPodLogsByAppName for ${SEARCH}"
}

echoInfo "Utilities loaded. Version ${VERSION}."
