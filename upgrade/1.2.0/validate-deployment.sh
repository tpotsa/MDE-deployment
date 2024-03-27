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

set -uo pipefail

## Main Script vars
readonly SCRIPT_NAME="${0##*/}"
printf -v NAME_PADDING '%*s ' ${#SCRIPT_NAME}

## Look & feel related vars
red=
green=
blue=
reset=
if [ -t 1 ]; then
  red=$(tput setaf 1)
  green=$(tput setaf 2)
  blue=$(tput setaf 4)
  reset=$(tput sgr0)
fi

## Format info messages with script name in green
info() {
  echo "${green}${SCRIPT_NAME}${reset}: ${1}" >&2
}

## Format error messages with script name in red
error() {
  echo "${red}${SCRIPT_NAME}${reset}: ${1}" >&2
}

if [[ $# -lt 2 ]]; then
  error "Not enough arguments supplied, usage:
$NAME_PADDING validate-deployment.sh PROJECT_ID DATASET_NAME"
  exit 1
fi

main() {
  check_args "${@}"
  info "--= Validation of ${blue}BigQuery Tables${reset} =--"
  check_bqtables "${@}"
  info "--= Validation of ${blue}GKE Workloads${reset} =--"
  check_gkeworkloads "${@}"
  info "--= Validation of ${blue}Dataflow Jobs${reset} =--"
  check_df_jobs "${@}"
  info "--= Validation of ${blue}GCS Buckets${reset} =--"
  check_gcs_buckets "${@}"
  info "--= Validation of ${blue}PubSub Topics${reset} =--"
  check_pubsub_topics "${@}"
}

check_args() {

  if [[ -z "$1" ]]; then
    error "Project ID can not be empty"
    exit 1
  fi

  if [[ -z "$2" ]]; then
    echo "Dataset Name can not be empty"
    exit 1
  fi

  if ! command -v gcloud &>/dev/null; then
    error "gcloud is required to run this script"
    exit 1
  fi

  if ! command -v bq &>/dev/null; then
    error "bq is required to run this script"
    exit 1
  fi

  PROJECT_ID=${1}
  DATASET_NAME=${2}
  USER=$(gcloud config get-value account 2>/dev/null)

  info "***** Welcome to the MDE Deployment Validation for version 1.2.0 *****
$NAME_PADDING This script will check for basic configuration matching ${blue}version 1.2.0${reset}
$NAME_PADDING PROJECT_ID set to ${blue}${PROJECT_ID}${reset}
$NAME_PADDING DATASET_NAME set to ${blue}${DATASET_NAME}${reset}
$NAME_PADDING You're authenticated as ${blue}${USER}${reset}"

  read -p "$NAME_PADDING Do you want to start the validation [Y/n]? " -n 1 -r
  if [[ $REPLY =~ ^[Nn]$ ]]; then
    exit 1
  fi
  echo ""
}

check_bqtables() {
  table_names=("NumericDataSeries" "DiscreteDataSeries" "ContinuousDataSeries" "ComponentDataSeries" "OperationsDashboard" "InsertErrors" "SchemaVersion")
  existing_table_names=$(bq ls sfp_data | tail -n +3 | tr -s ' ' | cut -d' ' -f2)
  for table_name in "${table_names[@]}"; do
    if [[ "$existing_table_names" != *"$table_name"* ]]; then
      error "Error: Could not find table ${red}${table_name}${reset} in dataset ${DATASET_NAME}"
    else
      info "Validated: Found ${blue}${table_name}${reset} in dataset ${DATASET_NAME}"
    fi
  done
}

check_gkeworkloads() {
  cluster_name="sfp-gke"
  cluster_location=$(gcloud container clusters list --filter="name:${cluster_name}" --format="value(LOCATION)")
  cluster_found=true

  if [[ $cluster_location == *"No cluster named"* ]]; then
    error "Error: Could not find cluster ${red}${cluster_name}${reset}"
    cluster_found=false
  else
    info "Validated: Found cluster ${blue}${cluster_name}${reset}"
  fi

  if [[ $cluster_found ]]; then
    info "Getting cluster credentials..."
    gcloud container clusters get-credentials "${cluster_name}" --region "${cluster_location}"
    export KUBE_CONFIG_PATH=~/.kube/config

    info "Getting Helm deployments..."

    check_helm_deployment config-manager ${cluster_name}
    check_helm_deployment federation-api ${cluster_name}
    check_helm_deployment timeseries ${cluster_name}
    check_helm_deployment workflows-deployer ${cluster_name}
  fi
}

check_helm_deployment() { #$1 = namespace $2 = cluster name
  deployment=$(helm list -n "$1")

  if [[ $deployment == *"deployed"* ]]; then
    info "Validated: Found Helm deployment ${blue}${1}${reset} on cluster ${2}"
  else
    error "Error: Could not find Helm deployment for ${red}${1}${reset} on cluster ${2}"
  fi
}

check_df_jobs() {
  check_df_job gcs-reader
  check_df_job message-payload-resolver
  check_df_job tag-enricher
  check_df_job tag-pipeline-runner
  check_df_job event-change-transformer
  check_df_job gcs-writer
  check_df_job gcs-raw-writer
  check_df_job bq-writer
  check_df_job timeseries-writer
  check_df_job ops-writer
}

check_df_job() {
  job_id=$(gcloud dataflow jobs list --status="active" --filter="name:${1}*" --format="value(JOB_ID)" 2>/dev/null)

  if [[ -z "$job_id" ]]; then
    error "Error: DataFlow job ${red}${1}${reset} is not in active state"
  else
    info "Validated: DataFlow job ${blue}${1}${reset} is active"
  fi
}

check_gcs_buckets() {
  buckets=$(gcloud storage ls 2>/dev/null)
  #info "All buckets in ${PROJECT_ID}: ${buckets}"
  check_gcs_bucket "${buckets}" "gs://${PROJECT_ID}-staging"
  check_gcs_bucket "${buckets}" "gs://${PROJECT_ID}-temp"
  check_gcs_bucket "${buckets}" "gs://${PROJECT_ID}-raw"
  check_gcs_bucket "${buckets}" "gs://${PROJECT_ID}-batch-ingestion"
  check_gcs_bucket "${buckets}" "gs://${PROJECT_ID}-config-manager-jobs"
}

check_gcs_bucket() { #$1 = buckets array $2 = bucket to check for
  if [[ "${1}" == *"${2}"* ]]; then
    info "Validated: GCS bucket ${blue}${2}${reset} found"
  else
    error "Error: GCS bucket ${red}${2}${reset} not found"
  fi
}

check_pubsub_topics() {
  topics=$(gcloud pubsub topics list 2>/dev/null)
  check_pubsub_topic "${topics}" "input-messages"
  check_pubsub_topic "${topics}" "tag-payload-resolved"
  check_pubsub_topic "${topics}" "tag-type-resolved"
  check_pubsub_topic "${topics}" "tag-enriched"
  check_pubsub_topic "${topics}" "tag-alerts"
  check_pubsub_topic "${topics}" "dead-letter"
  check_pubsub_topic "${topics}" "ingestion-operations"
}

check_pubsub_topic() {
  if [[ "${1}" == *"${2}"* ]]; then
    info "Validated: PubSub topic ${blue}${2}${reset} found"
  else
    error "Error: PubSub topic ${red}${2}${reset} not found"
  fi
}

main "${@}"
