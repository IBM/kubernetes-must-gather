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
  OPTIONS[logs-crashloopbackoff]=true
  OPTIONS[logs-etcd]=false
  OPTIONS[usage]=false

  ## Descriptions should always start with 'Enable '
  OPTIONS_BOOLEANS_DESCRIPTIONS[logs-crashloopbackoff]="Enable gathering pod logs of pods in CrashLoopBackOff state"
  OPTIONS_BOOLEANS_DESCRIPTIONS[logs-etcd]="Enable gathering pod logs of etcd pods"
  OPTIONS_BOOLEANS_DESCRIPTIONS[help]="Enable display of help/usage"
  OPTIONS_BOOLEANS_DESCRIPTIONS[usage]="Enable display of help/usage"
  OPTIONS_BOOLEANS_DESCRIPTIONS[all-pods-json]="Enable writing of JSON for all pods"

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
}

processCommandLine() {
  getopt --test 2> /dev/null
  if [ $? -ne 4 ]; then
    echoInfo "Enhanced getopt is required" >/dev/stderr
    exit 1
  fi

  echoInfo "processCommandLine:" "${@}"

  # Search specifically for --log=N because we might want logging of command line processing itself
  for arg; do
    case "$arg" in
      --log=*)
        OPTIONS[log]=${arg#--log=}
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
