#!/bin/bash
# Copyright IBM Corporation. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

MGOUTPUT="/must-gather"
BACKGROUND_PIDS=()
TEE_FILE="${MGOUTPUT}/kubernetes-must-gather.log"

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

# Same as echoInfo but only does anything if the log level is greater than or equal to 2
echoVerbose() {
  if [ ${OPTIONS[log]} -ge 2 ]; then
    echoInfo "${@}"
  fi
}

# Same as echoInfo but only does anything if the log level is greater than or equal to 3
echoVerbose3() {
  if [ ${OPTIONS[log]} -ge 3 ]; then
    echoInfo "${@}"
  fi
}

# Same as echoInfo but only does anything if the log level is greater than or equal to 3
echoVerbose4() {
  if [ ${OPTIONS[log]} -ge 4 ]; then
    echoInfo "${@}"
  fi
}

# Same as echoInfo but only does anything if the log level is greater than or equal to 3
echoVerbose5() {
  if [ ${OPTIONS[log]} -ge 5 ]; then
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
  echoInfo "Started $(basename "${0}"); version ${VERSION}"
}

queuedBackground() {
  BACKGROUND_PIDS+=($1)
}

endRun() {

  # Check if PID array has any values, if so, wait for them to finish
  echoInfo "Waiting on BACKGROUND_PIDS array: [${BACKGROUND_PIDS[@]}]"
  if [ ${#BACKGROUND_PIDS[@]} -ne 0 ]; then
    wait "${BACKGROUND_PIDS[@]}"
  fi

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
    BACKGROUND_PIDS+=($!)

    echoVerbose "Sparked off oc get pod ${ns}/${pod}; BACKGROUND_PIDS = ${BACKGROUND_PIDS[@]}"

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
    done <<< "${INPUT}" # Piping into the while loop would be a subshell and would lose any variable updates (e.g. BACKGROUND_PIDS)
  fi
  echoInfo "Finished getPodLogsByAppName for ${SEARCH}"
}

defaultProcessing() {
  # resource groups list
  group_resources=(nodes pods events securitycontextconstraints)

  filtered_group_resources=()
  for gr in "${group_resources[@]}"
  do
    oc get "$gr" > /dev/null 2>&1
    if [[ "$?" -eq 0 ]]; then
      filtered_group_resources+=("$gr")
    fi
  done

  group_resources_text=$(IFS=, ; echo "${filtered_group_resources[*]}")

  echoInfo "Calling main oc adm inspect with ${group_resources_text}"

  oc adm inspect --dest-dir "${MGOUTPUT}" --rotated-pod-logs "${group_resources_text}" --all-namespaces &
  queuedBackground $!

  echoInfo "Sparked off main oc adm inspect; BACKGROUND_PIDS = ${BACKGROUND_PIDS[@]}"

  if [ ${OPTIONS[all-pods-json]} = true ]; then
    ensureAllPodsJSON
  fi

  if [ ${OPTIONS[logs-crashloopbackoff]} = true ]; then
    echoInfo "Started checking for CrashLoopBackOff pods"
    ensureAllPodsJSON
    INPUT="$(echo "${ALL_PODS_JSON}" | jq -r '.items[] | select(.status.containerStatuses[]?.state.waiting?.reason == "CrashLoopBackOff") | [.metadata.namespace, .metadata.name] | @tsv')"
    if [ "${INPUT}" != "" ]; then
      while IFS=$'\t' read -r ns pod; do
        getPodLogs "${ns}" "${pod}"
      done <<< "${INPUT}" # Piping into the while loop would be a subshell and would lose any variable updates (e.g. BACKGROUND_PIDS)
    fi
    echoInfo "Finished checking for CrashLoopBackOff pods"
  fi

  if [ ${OPTIONS[logs-etcd]} = true ]; then
    echoInfo "Started checking for etcd pod logs"
    getPodLogsByAppName "etcd"
    getPodLogsByAppName "etcd-operator"
    echoInfo "Finished checking for etcd pod logs"
  fi

  echoInfo "Checking if we should call any included scripts"

  CURRENT_SCRIPT="$(basename "${0}")"
  for OTHER_SCRIPT in $(ls /usr/bin/gather*); do
    OTHER_SCRIPT_NAME="$(basename "${OTHER_SCRIPT}")"
    if [ "${OTHER_SCRIPT_NAME}" != "${CURRENT_SCRIPT}" ]; then
      echoVerbose3 "Other script ${OTHER_SCRIPT_NAME} = ${OPTIONS[${OTHER_SCRIPT_NAME}]}"
      if [ ${OPTIONS[${OTHER_SCRIPT_NAME}]} = true ]; then
        echoInfo "Executing script ${OTHER_SCRIPT_NAME}"
        #export BASE_COLLECTION_PATH="${MGOUTPUT}"
        /bin/bash "${OTHER_SCRIPT}"
        echoInfo "Finished executing ${OTHER_SCRIPT_NAME}"
      fi
    fi
  done
}
