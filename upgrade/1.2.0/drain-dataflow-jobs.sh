#!/usr/bin/env bash
# Copyright 2021 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -euo pipefail

## Main Script vars
readonly SCRIPT_NAME="${0##*/}"
printf -v NAME_PADDING '%*s ' ${#SCRIPT_NAME}

## Look & feel related vars
red=
green=
blue=
yellow=
reset=
if [ -t 1 ]; then
  red=$(tput setaf 1)
  green=$(tput setaf 2)
  yellow=$(tput setaf 3)
  blue=$(tput setaf 4)
  reset=$(tput sgr0)
fi

## Format info messages with script name in green
info() {
  echo "${green}${SCRIPT_NAME}${reset}: ${1}" >&2
}

warning() {
  echo "${yellow}${SCRIPT_NAME}${reset}: ${1}" >&2
}

## Format error messages with script name in red
error() {
  echo "${red}${SCRIPT_NAME}${reset}: ${1}" >&2
}

main() {
  check_args "${@}"
  drain_jobs "${@}"
}

check_args() {
  if [[ $# -lt 1 ]]; then
    error "Not enough arguments supplied, usage:
$NAME_PADDING drain-dataflow-jobs.sh PROJECT_ID"
    exit 1
  fi

  if [[ -z "$1" ]]; then
    error "Project ID can not be empty"
    exit 1
  fi

  if ! command -v gcloud &>/dev/null; then
    error "gcloud is required to run this script"
    exit 1
  fi

  PROJECT_ID=${1}
  USER=$(gcloud config get-value account 2>/dev/null)

  info "***** Welcome to the MDE Dataflow Jobs Draining Script *****
$NAME_PADDING This script will drain all currently running MDE dataflow jobs
$NAME_PADDING this is needed in order to upgrade to the latest version of MDE.
$NAME_PADDING None of the data in flight should be lost as PubSub will act as buffer.
$NAME_PADDING PROJECT_ID set to ${blue}${PROJECT_ID}${reset}
$NAME_PADDING You're authenticated as ${blue}${USER}${reset}
$NAME_PADDING This script is intended to be run as a Dataflow Administrator."

  read -p "$NAME_PADDING Are you sure you want to continue [Y/n]? " -n 1 -r
  if [[ $REPLY =~ ^[Nn]$ ]]; then
    exit 1
  fi
  echo ""
}

drain_jobs() {
  drain_dfjob gcs-reader
  drain_dfjob message-payload-resolver
  drain_dfjob tag-enricher
  drain_dfjob tag-pipeline-runner
  drain_dfjob event-change-transformer
  drain_dfjob gcs-writer
  drain_dfjob gcs-raw-writer
  drain_dfjob bq-writer
  drain_dfjob timeseries-writer
  drain_dfjob ops-writer
}

checkExec() {
  if [ "$1" -ne 0 ]; then
    error "Execution failed! ${@:2} -> Stopping script."
    exit "$1"
  fi
}

drain_dfjob() {
  job_ids=$(gcloud dataflow jobs list --status="active" --filter="name:${1}*" --format="value(JOB_ID)" 2>/dev/null)
  checkExec $? "Unable to load DataflowJobs, please check permissions. Error: $job_ids "
  if [[ -z "$job_ids" ]]; then
    warning "DataFlow job ${1} not in active state"
  else
    for jobid in ${job_ids}; do
      job_status=$(gcloud dataflow jobs list --status="all" --filter="id:${jobid}*" --format="value(STATE)" 2>/dev/null)
      if [ "${job_status}" = "Running" ]; then
        job_region=$(gcloud dataflow jobs list --status="all" --filter="id:${jobid}*" --format="value(REGION)" 2>/dev/null)
        checkExec $?
        info "Draining DataFlow job ${1} with id: ${jobid} in ${job_region} ${job_status}"
        gcloud dataflow jobs drain --region="${job_region}" "${jobid}"
        checkExec $?
      else
        info "DataFlow job ${1} with id: ${jobid} in ${job_region} is already in status: ${job_status}"
      fi
    done
  fi
}

main "${@}"
