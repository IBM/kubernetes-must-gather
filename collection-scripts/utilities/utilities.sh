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
  if [[ ${OPTIONS[log]} -ge 2 ]]; then
    echoInfo "${@}"
  fi
}

# Same as echoInfo but only does anything if the log level is greater than or equal to 3
echoVerbose3() {
  if [[ ${OPTIONS[log]} -ge 3 ]]; then
    echoInfo "${@}"
  fi
}

# Same as echoInfo but only does anything if the log level is greater than or equal to 3
echoVerbose4() {
  if [[ ${OPTIONS[log]} -ge 4 ]]; then
    echoInfo "${@}"
  fi
}

# Same as echoInfo but only does anything if the log level is greater than or equal to 3
echoVerbose5() {
  if [[ ${OPTIONS[log]} -ge 5 ]]; then
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
  if [[ ${OPTIONS[log]} -gt 1 ]]; then
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
  if [[ ${#BACKGROUND_PIDS[@]} -ne 0 ]]; then
    wait "${BACKGROUND_PIDS[@]}"
  fi

  echoInfo "Finished $(basename "${0}")"

  # force disk flush to ensure that all data gathered is accessible in the copy container
  sync

  echoInfo "sync finished"
}

ensureAllPodsJSON() {
  if [[ "${ALL_PODS_JSON}" = "" ]]; then
    echoInfo "Gathering all pods JSON"

    ALL_PODS_JSON="$(oc get pods -A -o json)"

    echoInfo "Finished gathering all pods JSON. Lines: $(echo "${ALL_PODS_JSON}" | wc -l)"

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
    queuedBackground $!

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
  if [[ "${INPUT}" != "" ]]; then
    while IFS=$'\t' read -r ns pod; do
      getPodLogs "${ns}" "${pod}"
    done <<< "${INPUT}" # Piping into the while loop would be a subshell and would lose any variable updates (e.g. BACKGROUND_PIDS)
  fi
  echoInfo "Finished getPodLogsByAppName for ${SEARCH}"
}

defaultProcessing() {

  echoInfo "Started defaultProcessing"

  if isOptionSet all-pods-json; then
    ensureAllPodsJSON
  fi

  # Named resource list, eg. ns/openshift-config
  named_resources=()

  # Resource groups list, eg. pods
  group_resources=()

  # Resources to gather with `--all-namespaces` option
  all_ns_resources=()
  
  if isOptionSet resources-nodes-allnamespaces; then
    all_ns_resources+=(nodes)
  fi
  if isOptionSet resources-pods-allnamespaces; then
    all_ns_resources+=(pods)
  fi
  if isOptionSet resources-events-allnamespaces; then
    all_ns_resources+=(events)
  fi
  if isOptionSet resources-securitycontextconstraints-allnamespaces; then
    all_ns_resources+=(securitycontextconstraints)
  fi

  # Cluster Version Information
  if isOptionSet cluster-version-resources ${OPTION_TYPE_OCP_GATHER}; then
    named_resources+=(ns/openshift-cluster-version)
    group_resources+=(clusterversion)
  fi

  # Operator and APIService Resources
  if isOptionSet operator-apiservice-resources ${OPTION_TYPE_OCP_GATHER}; then
    group_resources+=(clusteroperators apiservices)
  fi

  # Certificate Resources
  if isOptionSet certificate-resources ${OPTION_TYPE_OCP_GATHER}; then
    group_resources+=(certificatesigningrequests)
  fi

  # Machine/Node Resources
  if isOptionSet node-resources ${OPTION_TYPE_OCP_GATHER}; then
    group_resources+=(nodes)
  fi

  # Namespaces/Project Resources
  if isOptionSet namespace-resources ${OPTION_TYPE_OCP_GATHER}; then
    named_resources+=(ns/default ns/openshift ns/kube-system ns/openshift-etcd)
  fi

  # Storage Resources
  if isOptionSet storage-resources ${OPTION_TYPE_OCP_GATHER}; then
    group_resources+=(storageclasses persistentvolumes volumeattachments csidrivers csinodes volumesnapshotclasses volumesnapshotcontents clustercsidrivers)
    all_ns_resources+=(csistoragecapacities)
  fi

  # Image-source Resources
  if isOptionSet image-source-resources ${OPTION_TYPE_OCP_GATHER}; then
    group_resources+=(imagecontentsourcepolicies.operator.openshift.io)
  fi

  # Networking Resources
  if isOptionSet networking-resources ${OPTION_TYPE_OCP_GATHER}; then
    group_resources+=(networks.operator.openshift.io)
  fi

  # NodeNetworkState
  if isOptionSet nodenetworkstates ${OPTION_TYPE_OCP_GATHER}; then
    resources+=(nodenetworkstates nodenetworkconfigurationenactments nodenetworkconfigurationpolicies)
  fi

  # Assisted Installer
  if isOptionSet assisted-installer ${OPTION_TYPE_OCP_GATHER}; then
    named_resources+=(ns/assisted-installer)
  fi

  # Leases
  if isOptionSet leases ${OPTION_TYPE_OCP_GATHER}; then
    all_ns_resources+=(leases)
  fi

  # Flowcontrol - API Priority and Fairness (APF)
  if isOptionSet flowcontrol ${OPTION_TYPE_OCP_GATHER}; then
    group_resources+=(prioritylevelconfigurations.flowcontrol.apiserver.k8s.io flowschemas.flowcontrol.apiserver.k8s.io)
  fi

  # ClusterResourceQuota
  if isOptionSet clusterresourcequotas ${OPTION_TYPE_OCP_GATHER}; then
    group_resources+=(clusterresourcequotas.quota.openshift.io)
  fi

  # Run the Collection of Resources using inspect
  # running across all-namespaces for the few "Autoscaler" resources.
  if [[ ${#named_resources[@]} -ne 0 ]]; then
    echoInfo "Requesting named resources ${named_resources[@]}"
    oc adm inspect ${log_collection_args} --dest-dir "${MGOUTPUT}" --rotated-pod-logs "${named_resources[@]}" &
    queuedBackground $!
  fi

  filtered_group_resources=()
  for gr in "${group_resources[@]}"
  do
    oc get "$gr" > /dev/null 2>&1
    if [[ "$?" -eq 0 ]]; then
      filtered_group_resources+=("$gr")
    fi
  done
  group_resources_text=$(IFS=, ; echo "${filtered_group_resources[*]}")
  if [[ "${group_resources_text}" != "" ]]; then
    echoInfo "Requesting group resources ${group_resources_text}"
    oc adm inspect ${log_collection_args} --dest-dir "${MGOUTPUT}" --rotated-pod-logs "${group_resources_text}" &
    queuedBackground $!
  fi

  all_ns_resources_text=$(IFS=, ; echo "${all_ns_resources[*]}")
  if [[ "${all_ns_resources_text}" != "" ]]; then
    echoInfo "Requesting all namespace resources ${all_ns_resources_text}"
    oc adm inspect ${log_collection_args} --dest-dir "${MGOUTPUT}" --rotated-pod-logs "${all_ns_resources_text}" --all-namespaces &
    queuedBackground $!
  fi

  # Gather Insights Operator Archives
  if isOptionSet insights-operator ${OPTION_TYPE_OCP_GATHER}; then
    /usr/bin/gather_insights &
    queuedBackground $!
  fi

  # Gather monitoring data from the cluster
  if isOptionSet monitoring-data ${OPTION_TYPE_OCP_GATHER}; then
    /usr/bin/gather_monitoring &
    queuedBackground $!
  fi

  # Gather optional operator resources from all namespaces
  if isOptionSet olm-resources ${OPTION_TYPE_OCP_GATHER}; then
    /usr/bin/gather_olm &
    queuedBackground $!
  fi

  # Gather API Priority and Fairness Endpoints
  if isOptionSet api-priority-fairness ${OPTION_TYPE_OCP_GATHER}; then
    /usr/bin/gather_priority_and_fairness &
    queuedBackground $!
  fi

  # Gather etcd information
  if isOptionSet etcd ${OPTION_TYPE_OCP_GATHER}; then
    /usr/bin/gather_etcd &
    queuedBackground $!
  fi

  # Gather Service Logs (using a supplemental Script); Scoped to Masters.
  if isOptionSet service-logs ${OPTION_TYPE_OCP_GATHER}; then
    /usr/bin/gather_service_logs master &
    queuedBackground $!
  fi

  # Gather Windows Kubernetes component logs
  if isOptionSet windows-node-logs ${OPTION_TYPE_OCP_GATHER}; then
    /usr/bin/gather_windows_node_logs &
    queuedBackground $!
  fi

  # Gather HAProxy config files
  if isOptionSet haproxy-config ${OPTION_TYPE_OCP_GATHER}; then
    /usr/bin/gather_haproxy_config &
    queuedBackground $!
  fi

  # Gather kas startup and termination logs
  if isOptionSet kas-startup-termination ${OPTION_TYPE_OCP_GATHER}; then
    /usr/bin/gather_kas_startup_termination_logs &
    queuedBackground $!
  fi

  # Gather network logs
  if isOptionSet logs-network ${OPTION_TYPE_OCP_GATHER}; then
    /usr/bin/gather_network_logs_basics &
    queuedBackground $!
  fi

  # Gather metallb logs
  if isOptionSet logs-metallb ${OPTION_TYPE_OCP_GATHER}; then
    /usr/bin/gather_metallb &
    queuedBackground $!
  fi

  # Gather frr-k8s logs
  if isOptionSet logs-frr-k8s ${OPTION_TYPE_OCP_GATHER}; then
    /usr/bin/gather_frrk8s &
    queuedBackground $!
  fi

  # Gather NMState
  if isOptionSet nmstate ${OPTION_TYPE_OCP_GATHER}; then
    /usr/bin/gather_nmstate &
    queuedBackground $!
  fi

  # Gather SR-IOV resources
  if isOptionSet sriov ${OPTION_TYPE_OCP_GATHER}; then
    /usr/bin/gather_sriov &
    queuedBackground $!
  fi

  # Gather PodNetworkConnectivityCheck
  if isOptionSet podnetworkconnectivitycheck ${OPTION_TYPE_OCP_GATHER}; then
    /usr/bin/gather_podnetworkconnectivitycheck &
    queuedBackground $!
  fi

  # Gather On-Disk MachineConfig files
  if isOptionSet machineconfig-ondisk ${OPTION_TYPE_OCP_GATHER}; then
    /usr/bin/gather_machineconfig_ondisk &
    queuedBackground $!
  fi

  # Gather On-Disk MachineConfigDaemon logs
  if isOptionSet logs-machineconfig-termination ${OPTION_TYPE_OCP_GATHER}; then
    /usr/bin/gather_machineconfigdaemon_termination_logs &
    queuedBackground $!
  fi

  # Gather vSphere resources. This is NOOP on non-vSphere platform.
  if isOptionSet vsphere ${OPTION_TYPE_OCP_GATHER}; then
    /usr/bin/gather_vsphere &
    queuedBackground $!
  fi

  # Gather Performance profile information
  if isOptionSet performance-profile ${OPTION_TYPE_OCP_GATHER}; then
    /usr/bin/gather_ppc &
    queuedBackground $!
  fi

  # Gather OSUS information
  if isOptionSet osus ${OPTION_TYPE_OCP_GATHER}; then
    /usr/bin/gather_osus &
    queuedBackground $!
  fi

  # Gather ARO information
  if isOptionSet aro ${OPTION_TYPE_OCP_GATHER}; then
    /usr/bin/gather_aro
  fi

  if isOptionSet logs-crashloopbackoff; then
    echoInfo "Started checking for CrashLoopBackOff pods"
    ensureAllPodsJSON
    INPUT="$(echo "${ALL_PODS_JSON}" | jq -r '.items[] | select(.status.containerStatuses[]?.state.waiting?.reason == "CrashLoopBackOff") | [.metadata.namespace, .metadata.name] | @tsv')"
    echoVerbose "Pods in CrashLoopBackOff: ${INPUT}"
    if [[ "${INPUT}" != "" ]]; then
      while IFS=$'\t' read -r ns pod; do
        getPodLogs "${ns}" "${pod}"
      done <<< "${INPUT}" # Piping into the while loop would be a subshell and would lose any variable updates (e.g. BACKGROUND_PIDS)
    fi
    echoInfo "Finished checking for CrashLoopBackOff pods"
  fi

  if isOptionSet logs-etcd; then
    echoInfo "Started checking for etcd pod logs"
    getPodLogsByAppName "etcd"
    getPodLogsByAppName "etcd-operator"
    echoInfo "Finished checking for etcd pod logs"
  fi

  echoVerbose "Checking if we should call any included scripts"

  CURRENT_SCRIPT="$(basename "${0}")"
  for OTHER_SCRIPT in $(ls /usr/bin/gather*); do
    OTHER_SCRIPT_NAME="$(basename "${OTHER_SCRIPT}")"
    if [[ "${OTHER_SCRIPT_NAME}" != "${CURRENT_SCRIPT}" ]]; then
      echoVerbose3 "Other script ${OTHER_SCRIPT_NAME} = ${OPTIONS[${OTHER_SCRIPT_NAME}]}"
      if isOptionSet ${OTHER_SCRIPT_NAME}; then
        echoInfo "Executing script ${OTHER_SCRIPT_NAME}"
        #export BASE_COLLECTION_PATH="${MGOUTPUT}"
        /bin/bash "${OTHER_SCRIPT}"
        echoInfo "Finished executing ${OTHER_SCRIPT_NAME}"
      fi
    fi
  done

  echoInfo "Finished defaultProcessing"
}
