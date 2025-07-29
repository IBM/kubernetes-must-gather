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

    echoInfo "Finsished gathering all pods JSON. Lines: $(echo "${ALL_PODS_JSON}" | wc -l)"

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

  if [[ ${OPTIONS[all-pods-json]} = true ]]; then
    ensureAllPodsJSON
  fi

  # Named resource list, eg. ns/openshift-config
  named_resources=()

  # Resource groups list, eg. pods
  group_resources=()

  # Resources to gather with `--all-namespaces` option
  all_ns_resources=()
  
  if [[ ${OPTIONS[resources-nodes-allnamespaces]} = true ]]; then
    all_ns_resources+=(nodes)
  fi
  if [[ ${OPTIONS[resources-pods-allnamespaces]} = true ]]; then
    all_ns_resources+=(pods)
  fi
  if [[ ${OPTIONS[resources-events-allnamespaces]} = true ]]; then
    all_ns_resources+=(events)
  fi
  if [[ ${OPTIONS[resources-securitycontextconstraints-allnamespaces]} = true ]]; then
    all_ns_resources+=(securitycontextconstraints)
  fi

  # Cluster Version Information
  if [[ ${OPTIONS[cluster-version-resources]} = true ]]; then
    named_resources+=(ns/openshift-cluster-version)
    group_resources+=(clusterversion)
  fi

  # Operator and APIService Resources
  if [[ ${OPTIONS[operator-apiservice-resources]} = true ]]; then
    group_resources+=(clusteroperators apiservices)
  fi

  # Certificate Resources
  if [[ ${OPTIONS[certificate-resources]} = true ]]; then
    group_resources+=(certificatesigningrequests)
  fi

  # Machine/Node Resources
  if [[ ${OPTIONS[node-resources]} = true ]]; then
    group_resources+=(nodes)
  fi

  # Namespaces/Project Resources
  if [[ ${OPTIONS[namespace-resources]} = true ]]; then
    named_resources+=(ns/default ns/openshift ns/kube-system ns/openshift-etcd)
  fi

  # Storage Resources
  if [[ ${OPTIONS[storage-resources]} = true ]]; then
    group_resources+=(storageclasses persistentvolumes volumeattachments csidrivers csinodes volumesnapshotclasses volumesnapshotcontents clustercsidrivers)
    all_ns_resources+=(csistoragecapacities)
  fi

  # Image-source Resources
  if [[ ${OPTIONS[image-source-resources]} = true ]]; then
    group_resources+=(imagecontentsourcepolicies.operator.openshift.io)
  fi

  # Networking Resources
  if [[ ${OPTIONS[networking-resources]} = true ]]; then
    group_resources+=(networks.operator.openshift.io)
  fi

  # NodeNetworkState
  if [[ ${OPTIONS[nodenetworkstates]} = true ]]; then
    resources+=(nodenetworkstates nodenetworkconfigurationenactments nodenetworkconfigurationpolicies)
  fi

  # Assisted Installer
  if [[ ${OPTIONS[assisted-installer]} = true ]]; then
    named_resources+=(ns/assisted-installer)
  fi

  # Leases
  if [[ ${OPTIONS[leases]} = true ]]; then
    all_ns_resources+=(leases)
  fi

  # Flowcontrol - API Priority and Fairness (APF)
  if [[ ${OPTIONS[flowcontrol]} = true ]]; then
    group_resources+=(prioritylevelconfigurations.flowcontrol.apiserver.k8s.io flowschemas.flowcontrol.apiserver.k8s.io)
  fi

  # ClusterResourceQuota
  if [[ ${OPTIONS[clusterresourcequotas]} = true ]]; then
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
  if [[ ${OPTIONS[insights-operator]} = true ]]; then
    /usr/bin/gather_insights &
    queuedBackground $!
  fi

  # Gather monitoring data from the cluster
  if [[ ${OPTIONS[monitoring-data]} = true ]]; then
    /usr/bin/gather_monitoring &
    queuedBackground $!
  fi

  # Gather optional operator resources from all namespaces
  if [[ ${OPTIONS[olm-resources]} = true ]]; then
    /usr/bin/gather_olm &
    queuedBackground $!
  fi

  # Gather API Priority and Fairness Endpoints
  if [[ ${OPTIONS[api-priority-fairness]} = true ]]; then
    /usr/bin/gather_priority_and_fairness &
    queuedBackground $!
  fi

  # Gather etcd information
  if [[ ${OPTIONS[etcd]} = true ]]; then
    /usr/bin/gather_etcd &
    queuedBackground $!
  fi

  # Gather Service Logs (using a supplemental Script); Scoped to Masters.
  if [[ ${OPTIONS[service-logs]} = true ]]; then
    /usr/bin/gather_service_logs master &
    queuedBackground $!
  fi

  # Gather Windows Kubernetes component logs
  if [[ ${OPTIONS[windows-node-logs]} = true ]]; then
    /usr/bin/gather_windows_node_logs &
    queuedBackground $!
  fi

  # Gather HAProxy config files
  if [[ ${OPTIONS[haproxy-config]} = true ]]; then
    /usr/bin/gather_haproxy_config &
    queuedBackground $!
  fi

  # Gather kas startup and termination logs
  if [[ ${OPTIONS[kas-startup-termination]} = true ]]; then
    /usr/bin/gather_kas_startup_termination_logs &
    queuedBackground $!
  fi

  # Gather network logs
  if [[ ${OPTIONS[logs-network]} = true ]]; then
    /usr/bin/gather_network_logs_basics &
    queuedBackground $!
  fi

  # Gather metallb logs
  if [[ ${OPTIONS[logs-metallb]} = true ]]; then
    /usr/bin/gather_metallb &
    queuedBackground $!
  fi

  # Gather frr-k8s logs
  if [[ ${OPTIONS[logs-frr-k8s]} = true ]]; then
    /usr/bin/gather_frrk8s &
    queuedBackground $!
  fi

  # Gather NMState
  if [[ ${OPTIONS[nmstate]} = true ]]; then
    /usr/bin/gather_nmstate &
    queuedBackground $!
  fi

  # Gather SR-IOV resources
  if [[ ${OPTIONS[sriov]} = true ]]; then
    /usr/bin/gather_sriov &
    queuedBackground $!
  fi

  # Gather PodNetworkConnectivityCheck
  if [[ ${OPTIONS[podnetworkconnectivitycheck]} = true ]]; then
    /usr/bin/gather_podnetworkconnectivitycheck &
    queuedBackground $!
  fi

  # Gather On-Disk MachineConfig files
  if [[ ${OPTIONS[machineconfig-ondisk]} = true ]]; then
    /usr/bin/gather_machineconfig_ondisk &
    queuedBackground $!
  fi

  # Gather On-Disk MachineConfigDaemon logs
  if [[ ${OPTIONS[logs-machineconfig-termination]} = true ]]; then
    /usr/bin/gather_machineconfigdaemon_termination_logs &
    queuedBackground $!
  fi

  # Gather vSphere resources. This is NOOP on non-vSphere platform.
  if [[ ${OPTIONS[vsphere]} = true ]]; then
    /usr/bin/gather_vsphere &
    queuedBackground $!
  fi

  # Gather Performance profile information
  if [[ ${OPTIONS[performance-profile]} = true ]]; then
    /usr/bin/gather_ppc &
    queuedBackground $!
  fi

  # Gather OSUS information
  if [[ ${OPTIONS[osus]} = true ]]; then
    /usr/bin/gather_osus &
    queuedBackground $!
  fi

  # Gather ARO information
  if [[ ${OPTIONS[aro]} = true ]]; then
    /usr/bin/gather_aro
  fi

  if [[ ${OPTIONS[logs-crashloopbackoff]} = true ]]; then
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

  if [[ ${OPTIONS[logs-etcd]} = true ]]; then
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
      if [[ ${OPTIONS[${OTHER_SCRIPT_NAME}]} = true ]]; then
        echoInfo "Executing script ${OTHER_SCRIPT_NAME}"
        #export BASE_COLLECTION_PATH="${MGOUTPUT}"
        /bin/bash "${OTHER_SCRIPT}"
        echoInfo "Finished executing ${OTHER_SCRIPT_NAME}"
      fi
    fi
  done

  echoInfo "Finished defaultProcessing"
}
