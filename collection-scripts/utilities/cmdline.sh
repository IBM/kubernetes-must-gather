#!/bin/bash
# Copyright IBM Corporation. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

declare -A OPTIONS=()
declare -A OPTIONS_BOOLEANS_DESCRIPTIONS=()
declare -A OPTIONS_SHORTFLAGS=()
declare -A OPTIONS_FLAGS_ARG_REQUIRED_DESCRIPTIONS=()
declare -A OPTIONS_FLAGS_ARG_NOT_REQUIRED_DESCRIPTIONS=()
declare -A OPTIONS_FLAGS_ARG_NOT_REQUIRED_DEFAULTS=()
declare -A OPTIONS_BOOLEANS_SKIPNO=()

setDefaultFlags() {
  # Option defaults
  OPTIONS[all-pods-json]=false
  OPTIONS[help]=false
  OPTIONS[log]=1
  OPTIONS[logs-crashloopbackoff]=false
  OPTIONS[logs-etcd]=false
  OPTIONS[usage]=false
  OPTIONS[resources-nodes-allnamespaces]=false
  OPTIONS[resources-pods-allnamespaces]=false
  OPTIONS[resources-events-allnamespaces]=false
  OPTIONS[resources-securitycontextconstraints-allnamespaces]=false
  OPTIONS[cluster-version-resources]=false
  OPTIONS[operator-apiservice-resources]=false
  OPTIONS[certificate-resources]=false
  OPTIONS[node-resources]=false
  OPTIONS[namespace-resources]=false
  OPTIONS[storage-resources]=false
  OPTIONS[image-source-resources]=false
  OPTIONS[networking-resources]=false
  OPTIONS[nodenetworkstates]=false
  OPTIONS[assisted-installer]=false
  OPTIONS[leases]=false
  OPTIONS[flowcontrol]=false
  OPTIONS[clusterresourcequotas]=false
  OPTIONS[insights-operator]=false
  OPTIONS[monitoring-data]=false
  OPTIONS[olm-resources]=false
  OPTIONS[api-priority-fairness]=false
  OPTIONS[etcd]=false
  OPTIONS[service-logs]=false
  OPTIONS[windows-node-logs]=false
  OPTIONS[haproxy-config]=false
  OPTIONS[kas-startup-termination]=false
  OPTIONS[logs-network]=false
  OPTIONS[logs-metallb]=false
  OPTIONS[logs-frr-k8s]=false
  OPTIONS[nmstate]=false
  OPTIONS[sriov]=false
  OPTIONS[podnetworkconnectivitycheck]=false
  OPTIONS[machineconfig-ondisk]=false
  OPTIONS[logs-machineconfig-termination]=false
  OPTIONS[vsphere]=false
  OPTIONS[performance-profile]=false
  OPTIONS[osus]=false
  OPTIONS[aro]=false
  OPTIONS[use-default-options]=false

  ## Descriptions should always start with 'Enable '
  OPTIONS_BOOLEANS_DESCRIPTIONS[logs-crashloopbackoff]="Enable gathering pod logs of pods in CrashLoopBackOff state"
  OPTIONS_BOOLEANS_DESCRIPTIONS[logs-etcd]="Enable gathering pod logs of etcd pods"
  OPTIONS_BOOLEANS_DESCRIPTIONS[help]="Enable display of help/usage"
  OPTIONS_BOOLEANS_DESCRIPTIONS[usage]="Enable display of help/usage"
  OPTIONS_BOOLEANS_DESCRIPTIONS[all-pods-json]="Enable writing of JSON for all pods"
  OPTIONS_BOOLEANS_DESCRIPTIONS[resources-nodes-allnamespaces]="Enable gathering resource YAMLs of nodes in all namespaces"
  OPTIONS_BOOLEANS_DESCRIPTIONS[resources-pods-allnamespaces]="Enable gathering resource YAMLs of pods in all namespaces"
  OPTIONS_BOOLEANS_DESCRIPTIONS[resources-events-allnamespaces]="Enable gathering resource YAMLs of events in all namespaces"
  OPTIONS_BOOLEANS_DESCRIPTIONS[resources-securitycontextconstraints-allnamespaces]="Enable gathering resource YAMLs of securitycontextconstraints in all namespaces"
  OPTIONS_BOOLEANS_DESCRIPTIONS[cluster-version-resources]="Enable gathering cluster version resources"
  OPTIONS_BOOLEANS_DESCRIPTIONS[operator-apiservice-resources]="Enable gathering operator and APIservice resources"
  OPTIONS_BOOLEANS_DESCRIPTIONS[certificate-resources]="Enable gathering certificate resources"
  OPTIONS_BOOLEANS_DESCRIPTIONS[node-resources]="Enable gathering node resources"
  OPTIONS_BOOLEANS_DESCRIPTIONS[namespace-resources]="Enable gathering namespaces resources"
  OPTIONS_BOOLEANS_DESCRIPTIONS[storage-resources]="Enable gathering storage resources"
  OPTIONS_BOOLEANS_DESCRIPTIONS[image-source-resources]="Enable gathering image-source resources"
  OPTIONS_BOOLEANS_DESCRIPTIONS[networking-resources]="Enable gathering networking resources"
  OPTIONS_BOOLEANS_DESCRIPTIONS[nodenetworkstates]="Enable gathering nodenetworkstate resources"
  OPTIONS_BOOLEANS_DESCRIPTIONS[assisted-installer]="Enable gathering assisted-installer resources"
  OPTIONS_BOOLEANS_DESCRIPTIONS[leases]="Enable gathering lease resources"
  OPTIONS_BOOLEANS_DESCRIPTIONS[flowcontrol]="Enable gathering flowcontrol resources"
  OPTIONS_BOOLEANS_DESCRIPTIONS[clusterresourcequotas]="Enable gathering clusterresourcequota resources"
  OPTIONS_BOOLEANS_DESCRIPTIONS[insights-operator]="Enable gathering insights-operator resources"
  OPTIONS_BOOLEANS_DESCRIPTIONS[monitoring-data]="Enable gathering monitoring data"
  OPTIONS_BOOLEANS_DESCRIPTIONS[olm-resources]="Enable gathering OLM resources"
  OPTIONS_BOOLEANS_DESCRIPTIONS[api-priority-fairness]="Enable gathering API priority and fairness resources"
  OPTIONS_BOOLEANS_DESCRIPTIONS[etcd]="Enable gathering etcd resources"
  OPTIONS_BOOLEANS_DESCRIPTIONS[service-logs]="Enable gathering service logs"
  OPTIONS_BOOLEANS_DESCRIPTIONS[windows-node-logs]="Enable gathering Windows node logs"
  OPTIONS_BOOLEANS_DESCRIPTIONS[haproxy-config]="Enable gathering HAProxy config"
  OPTIONS_BOOLEANS_DESCRIPTIONS[kas-startup-termination]="Enable gathering KAS startup termination"
  OPTIONS_BOOLEANS_DESCRIPTIONS[logs-network]="Enable gathering network logs"
  OPTIONS_BOOLEANS_DESCRIPTIONS[logs-metallb]="Enable gathering metallb logs"
  OPTIONS_BOOLEANS_DESCRIPTIONS[logs-frr-k8s]="Enable gathering frr-k8s resources"
  OPTIONS_BOOLEANS_DESCRIPTIONS[nmstate]="Enable gathering nmstate resources"
  OPTIONS_BOOLEANS_DESCRIPTIONS[sriov]="Enable gathering sriov resources"
  OPTIONS_BOOLEANS_DESCRIPTIONS[podnetworkconnectivitycheck]="Enable gathering podnetworkconnectivitycheck resources"
  OPTIONS_BOOLEANS_DESCRIPTIONS[machineconfig-ondisk]="Enable gathering machineconfig ondisk resources"
  OPTIONS_BOOLEANS_DESCRIPTIONS[logs-machineconfig-termination]="Enable gathering machineconfig termination logs"
  OPTIONS_BOOLEANS_DESCRIPTIONS[vsphere]="Enable gathering VSphere resources"
  OPTIONS_BOOLEANS_DESCRIPTIONS[performance-profile]="Enable gathering performance profile resources"
  OPTIONS_BOOLEANS_DESCRIPTIONS[osus]="Enable gathering osus resources"
  OPTIONS_BOOLEANS_DESCRIPTIONS[aro]="Enable gathering ARO resources"
  OPTIONS_BOOLEANS_DESCRIPTIONS[use-default-options]="Enable resetting overridden script options"

  # Optional short-hand flags for options
  OPTIONS_SHORTFLAGS[help]=h
  OPTIONS_SHORTFLAGS[log]=v
  OPTIONS_SHORTFLAGS[logs-crashloopbackoff]=c
  OPTIONS_SHORTFLAGS[usage]=u

  OPTIONS_FLAGS_ARG_NOT_REQUIRED_DESCRIPTIONS[log]="Script log level from 0-2 (higher is more verbose)"

  # Flag defaults
  OPTIONS_FLAGS_ARG_NOT_REQUIRED_DEFAULTS[log]=2

  # For boolean options, do not add a --no- option
  OPTIONS_BOOLEANS_SKIPNO[usage]=true
  OPTIONS_BOOLEANS_SKIPNO[help]=true
  OPTIONS_BOOLEANS_SKIPNO[use-default-options]=true
}

processCommandLine() {
  getopt --test 2> /dev/null
  if [ $? -ne 4 ]; then
    echoInfo "Enhanced getopt is required" >/dev/stderr
    exit 1
  fi

  echoInfo "processCommandLine:" "${@}"

  # Search specifically for a few things because we might want to change/log command line processing itself
  for arg; do
    case "$arg" in
      --log=*)
        OPTIONS[log]=${arg#--log=}
        ;;
      --use-default-options)
        setDefaultFlags
        ;;
    esac
  done

  CURRENT_SCRIPT="$(basename "${0}")"
  for OTHER_SCRIPT in $(ls /usr/bin/gather*); do
    OTHER_SCRIPT="$(basename "${OTHER_SCRIPT}")"
    if [ "${OTHER_SCRIPT}" != "${CURRENT_SCRIPT}" ]; then
      OPTIONS[${OTHER_SCRIPT}]=false
      OPTIONS_BOOLEANS_DESCRIPTIONS[${OTHER_SCRIPT}]="Enable execution of ${OTHER_SCRIPT}. See https://github.com/openshift/must-gather/blob/main/collection-scripts/${OTHER_SCRIPT}"
    fi
  done

  # Option pre-processing (e.g. add no- flags)
  for OPTION in "${!OPTIONS_BOOLEANS_DESCRIPTIONS[@]}"; do
    if ! [[ -v OPTIONS_BOOLEANS_SKIPNO[${OPTION}] ]]; then
      OPTIONS_BOOLEANS_DESCRIPTIONS["no-${OPTION}"]="Disable ${OPTIONS_BOOLEANS_DESCRIPTIONS[${OPTION}]#Enable }"
    fi
  done

  # Option processing

  GETOPTS_SHORT=""
  GETOPTS_LONG=""
  for OPTION in "${!OPTIONS[@]}"; do
    if [ "${GETOPTS_LONG}" != "" ]; then
      GETOPTS_LONG="${GETOPTS_LONG},"
    fi
    GETOPTS_LONG="${GETOPTS_LONG}${OPTION}"
    if [[ -v OPTIONS_FLAGS_ARG_REQUIRED_DESCRIPTIONS[${OPTION}] ]]; then
      GETOPTS_LONG="${GETOPTS_LONG}:"
    elif [[ -v OPTIONS_FLAGS_ARG_NOT_REQUIRED_DESCRIPTIONS[${OPTION}] ]]; then
      GETOPTS_LONG="${GETOPTS_LONG}::"
    fi

    if [[ -v OPTIONS_BOOLEANS_DESCRIPTIONS[${OPTION}] ]] && ! [[ -v OPTIONS_BOOLEANS_SKIPNO[${OPTION}] ]]; then
      GETOPTS_LONG="${GETOPTS_LONG},no-${OPTION}"
    fi

    if [[ -v OPTIONS_SHORTFLAGS[${OPTION}] ]]; then
      SHORT_FLAG="${OPTIONS_SHORTFLAGS[${OPTION}]}"
      GETOPTS_SHORT="${GETOPTS_SHORT}${SHORT_FLAG}"
      if [[ -v OPTIONS_FLAGS_ARG_REQUIRED_DESCRIPTIONS[${OPTION}] ]]; then
        GETOPTS_SHORT="${GETOPTS_SHORT}:"
      elif [[ -v OPTIONS_FLAGS_ARG_NOT_REQUIRED_DESCRIPTIONS[${OPTION}] ]]; then
        GETOPTS_SHORT="${GETOPTS_SHORT}::"
      fi
    fi
  done

  echoVerbose5 "GETOPTS_SHORT = ${GETOPTS_SHORT}"
  echoVerbose5 "GETOPTS_LONG = ${GETOPTS_LONG}"

  # https://www.kernel.org/doc/man-pages/online/pages/man1/getopt.1.html
  PARSED=$(getopt --alternative --options "-${GETOPTS_SHORT}" --longoptions "${GETOPTS_LONG}" --name "$0" -- "$@")
  if [ $? -ne 0 ]; then
    # Invalid argument and getopt printed the error
    exit 2
  fi

  eval set -- "${PARSED}"

  POSITIONAL_ARGS=()

  for arg in "${@}"; do
    echoVerbose5 "Arg: ${arg}"
  done

  IN_POSITIONAL=false
  while [[ $# -gt 0 ]]; do
    case $1 in
      --)
        IN_POSITIONAL=true
        shift # past this argument
        ;;
      --*)
        OPTION="${1}"
        shift # past this argument

        if [ ${IN_POSITIONAL} = false ]; then
          if [[ -v OPTIONS_BOOLEANS_DESCRIPTIONS["${OPTION#--}"] ]]; then
            if [ "${OPTION#--no-}" = "${OPTION}" ]; then
              OPTIONS["${OPTION#--}"]=true
            else
              OPTIONS["${OPTION#--no-}"]=false
            fi
          else
            if [[ -v OPTIONS_FLAGS_ARG_REQUIRED_DESCRIPTIONS["${OPTION#--}"] ]]; then
              OPTIONS["${OPTION#--}"]=$1
              shift # past this argument
            elif [[ -v OPTIONS_FLAGS_ARG_NOT_REQUIRED_DESCRIPTIONS["${OPTION#--}"] ]]; then
              if [ "${1}" = "" ]; then
                OPTIONS["${OPTION#--}"]=${OPTIONS_FLAGS_ARG_NOT_REQUIRED_DEFAULTS[${OPTION}]}
              else
                OPTIONS["${OPTION#--}"]=$1
              fi
              shift # past this argument
            fi
          fi
        else
          POSITIONAL_ARGS+=("${OPTION}")
        fi

        ;;
      -*)
        FLAG="${1}"
        shift # past this argument

        if [ ${IN_POSITIONAL} = false ]; then
          OPTION=""
          for LONGFLAG in "${!OPTIONS_SHORTFLAGS[@]}"; do
            SHORTFLAG="${OPTIONS_SHORTFLAGS[${LONGFLAG}]}"
            if [ "${FLAG#-}" = "${SHORTFLAG}" ]; then
              OPTION="${LONGFLAG}"
            fi
          done

          if [[ -v OPTIONS_BOOLEANS_DESCRIPTIONS["${OPTION#--}"] ]]; then
            if [ "${OPTION#--no-}" = "${OPTION}" ]; then
              OPTIONS["${OPTION#--}"]=true
            else
              OPTIONS["${OPTION#--no-}"]=false
            fi
          else
            if [[ -v OPTIONS_FLAGS_ARG_REQUIRED_DESCRIPTIONS["${OPTION#--}"] ]]; then
              OPTIONS["${OPTION#--}"]=$1
              shift # past this argument
            elif [[ -v OPTIONS_FLAGS_ARG_NOT_REQUIRED_DESCRIPTIONS["${OPTION#--}"] ]]; then
              if [ "${1}" = "" ]; then
                OPTIONS["${OPTION#--}"]=${OPTIONS_FLAGS_ARG_NOT_REQUIRED_DEFAULTS[${OPTION}]}
              else
                OPTIONS["${OPTION#--}"]=$1
              fi
              shift # past this argument
            fi
          fi
        else
          POSITIONAL_ARGS+=("${FLAG}")
        fi

        ;;
      *)
        POSITIONAL_ARGS+=("${1}")
        shift # past this argument
        ;;
    esac
  done

  set -- "${POSITIONAL_ARGS[@]}" # restore positional parameters

  if [ ${OPTIONS[usage]} = true ] || [ ${OPTIONS[help]} = true ]; then
    usage
  fi

  echoInfo "Final options:"
  FINAL_OPTIONS="$(printFinalOptions | sort)"
  echoWithoutPrefix "${FINAL_OPTIONS}"
}

usageOptionsUnsorted() {
  for OPTION in "${!OPTIONS_BOOLEANS_DESCRIPTIONS[@]}"; do
    if [ "${OPTION#no-}" = "${OPTION}" ]; then
      printf "       "
      printf -- "--${OPTION}"
      if ! [[ -v OPTIONS_BOOLEANS_SKIPNO[${OPTION}] ]]; then
        printf -- " | --no-${OPTION}"
      fi
      if [[ -v OPTIONS_SHORTFLAGS[${OPTION}] ]]; then
        printf -- " | -${OPTIONS_SHORTFLAGS[${OPTION}]}"
      fi
      if ! [[ -v OPTIONS_BOOLEANS_SKIPNO[${OPTION}] ]]; then
        printf ": Enable/disable"
      else
        printf ": Enable"
      fi
      printf " ${OPTIONS_BOOLEANS_DESCRIPTIONS[${OPTION}]#Enable }."
      if ! [[ -v OPTIONS_BOOLEANS_SKIPNO[${OPTION}] ]]; then
        printf " Currently: "
        if [ ${OPTIONS[${OPTION}]} = true ]; then
          printf "Enabled"
        else
          printf "Disabled"
        fi
        printf "."
      fi

      printf "\n"
    fi
  done

  for OPTION in "${!OPTIONS_FLAGS_ARG_REQUIRED_DESCRIPTIONS[@]}"; do
    printf "       "
    printf -- "--${OPTION}=ARGUMENT"
    if [[ -v OPTIONS_SHORTFLAGS[${OPTION}] ]]; then
      printf -- " | -${OPTIONS_SHORTFLAGS[${OPTION}]}ARGUMENT"
    fi
    printf ": ${OPTIONS_FLAGS_ARG_REQUIRED_DESCRIPTIONS[${OPTION}]}. Currently: ${OPTIONS[${OPTION}]}."
    printf "\n"
  done

  for OPTION in "${!OPTIONS_FLAGS_ARG_NOT_REQUIRED_DESCRIPTIONS[@]}"; do
    printf "       "
    printf -- "--${OPTION}[=ARGUMENT[=${OPTIONS_FLAGS_ARG_NOT_REQUIRED_DEFAULTS[${OPTION}]}]]"
    if [[ -v OPTIONS_SHORTFLAGS[${OPTION}] ]]; then
      printf -- " | -${OPTIONS_SHORTFLAGS[${OPTION}]}[ARGUMENT[=${OPTIONS_FLAGS_ARG_NOT_REQUIRED_DEFAULTS[${OPTION}]}]]"
    fi
    printf ": ${OPTIONS_FLAGS_ARG_NOT_REQUIRED_DESCRIPTIONS[${OPTION}]}. Currently: ${OPTIONS[${OPTION}]}."
    printf "\n"
  done
}

usage() {
  printf "Usage: $(basename "${0}")\n"

  usageOptionsUnsorted | sort

  exit 22
}

printFinalOptions() {
  for OPTION in "${!OPTIONS[@]}"; do
    echo "  --${OPTION} = ${OPTIONS[${OPTION}]}"
  done
}
