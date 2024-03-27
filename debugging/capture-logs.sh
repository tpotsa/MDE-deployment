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
red=$(tput setaf 1)
green=$(tput setaf 2)
blue=$(tput setaf 4)
reset=$(tput sgr0)

## Format info messages with script name in green
info() {
  echo "${green}${SCRIPT_NAME}${reset}: ${1}" >&2
}

## Format error messages with script name in red
error() {
  echo "${red}${SCRIPT_NAME}${reset}: ${1}" >&2
}

main() {
  check_args "${@}"
  prepare_script "${@}"
  capture_workflows_logs "${@}"
  capture_gke_services_logs "${@}"
  capture_bigquery_logs "${@}"
  compress_logs "${@}"
}

check_args() {
  if [[ $# -lt 3 ]]; then
    error "Not enough arguments supplied, usage should be like:
$NAME_PADDING capture-logs.sh PROJECT_ID REGION DAYS_TO_CAPTURE BIGQUERY_PROJECT_ID
$NAME_PADDING BIGQUERY_PROJECT_ID is optional"
    exit 1
  fi

  if [[ -z "$1" ]]; then
    error "Project ID can not be empty"
    exit 1
  fi

  if [[ -z "$2" ]]; then
    error "Region can not be empty"
    exit 1
  fi

  if [[ -z "$3" ]]; then
    error "Days to capture can not be empty"
    exit 1
  fi

  if ! command -v gcloud &>/dev/null; then
    error "gcloud is required to run this script"
    exit 1
  fi

  PROJECT_ID=${1}
  REGION=${2}
  DAYS_TO_CAPTURE=${3}
  BIGQUERY_PROJECT_ID=$PROJECT_ID
  USER=$(gcloud config get-value account 2>/dev/null)

  if [[ $# -eq 4 ]]; then
    BIGQUERY_PROJECT_ID="${4}"
  fi

  info "***** Welcome to the MDE Log Capturing Script *****
$NAME_PADDING This script is intended to capture logs of the MDE system in case of an issue
$NAME_PADDING it will capture logs for the different systems:
$NAME_PADDING - Config Manager
$NAME_PADDING - Federation API
$NAME_PADDING - Timeseries
$NAME_PADDING - Workflows deployer
$NAME_PADDING - All the dataflow jobs
$NAME_PADDING - Errors written to OperationsDashboard and InsertErrors tables
$NAME_PADDING PROJECT_ID set to ${blue}${PROJECT_ID}${reset}
$NAME_PADDING REGION set to ${blue}${REGION}${reset}
$NAME_PADDING DAYS_TO_CAPTURE set to ${blue}${DAYS_TO_CAPTURE}${reset}
$NAME_PADDING BIGQUERY_PROJECT_ID set to ${blue}${BIGQUERY_PROJECT_ID}${reset}
$NAME_PADDING You're authenticated as ${blue}${USER}${reset}
$NAME_PADDING You'll need permissions to gather logs in all this services for the script to work."

  read -p "$NAME_PADDING Are you sure you want to continue [Y/n]? " -n 1 -r
  if [[ $REPLY =~ ^[Nn]$ ]]; then
    exit 1
  fi
  echo ""
}

prepare_script() {
  info "Setting gcloud project to ${PROJECT_ID}"
  gcloud config set project "$PROJECT_ID"

  FOLDER_NAME="mde-logs-$(date +"%F_%H-%M-%S-%Z")"

  info "Creating ${FOLDER_NAME} folder to save logs."
  mkdir "$FOLDER_NAME"

  mkdir "$FOLDER_NAME/dataflow"
  mkdir "$FOLDER_NAME/services"
  mkdir "$FOLDER_NAME/bigquery"
}

capture_workflows_logs() {
  WORKFLOWS=$(gcloud dataflow jobs list --region="$REGION" --format="value[separator=';',terminator=' '](JOB_ID,NAME)" --project="$PROJECT_ID" --filter=STATE:Running)

  info "Capturing Dataflow jobs logs"

  for workflow in $WORKFLOWS; do
    workflowArray=(${workflow//;/ })
    jobId=${workflowArray[0]}
    jobName=${workflowArray[1]}
    info "Capturing logs for job: ${jobName} with JobId: ${jobId}"

    gcloud logging read 'resource.type="dataflow_step" AND resource.labels.job_id='"${jobId}"' AND logName=("projects/imde-eap-ford-dev/logs/dataflow.googleapis.com%2Fjob-message"  OR "projects/imde-eap-ford-dev/logs/dataflow.googleapis.com%2Flauncher") AND severity=WARNING' \
      --format json --freshness "${DAYS_TO_CAPTURE}"d >"${FOLDER_NAME}/dataflow/${jobName}-job.json"

    gcloud logging read 'resource.type="dataflow_step" AND resource.labels.job_id='"$jobId"' AND logName=("projects/imde-eap-ford-dev/logs/dataflow.googleapis.com%2Fworker" OR "projects/imde-eap-ford-dev/logs/dataflow.googleapis.com%2Fworker-startup") AND severity=WARNING' \
      --format json --freshness "$DAYS_TO_CAPTURE"d >"$FOLDER_NAME/dataflow/$jobName-worker.json"
  done
}

capture_gke_services_logs() {
  info "Capturing logs for the config-manager"
  gcloud logging read 'resource.type="k8s_container" resource.labels.project_id='"$PROJECT_ID"' resource.labels.location='"$REGION"' resource.labels.cluster_name="sfp-gke" resource.labels.namespace_name="config-manager"  labels.k8s-pod/app_kubernetes_io/instance="config-manager"  NOT resource.labels.container_name = "cloud-sql-proxy" labels.k8s-pod/app_kubernetes_io/name="config-manager" severity=ERROR' \
    --format json --freshness "$DAYS_TO_CAPTURE"d >"$FOLDER_NAME/services/config-manager.json"

  info "Capturing logs for the timeseries service"
  gcloud logging read 'resource.type="k8s_container" resource.labels.project_id='"$PROJECT_ID"' resource.labels.location='"$REGION"' resource.labels.cluster_name="sfp-gke" resource.labels.namespace_name="timeseries"  labels.k8s-pod/app_kubernetes_io/instance="timeseries"  labels.k8s-pod/app_kubernetes_io/name="timeseries" severity=ERROR' \
    --format json --freshness "$DAYS_TO_CAPTURE"d >"$FOLDER_NAME/services/timeseries.json"

  info "Capturing logs for the federation API service"
  gcloud logging read 'resource.type="k8s_container" resource.labels.project_id='"$PROJECT_ID"' resource.labels.location='"$REGION"' resource.labels.cluster_name="sfp-gke" resource.labels.namespace_name="federation-api"  labels.k8s-pod/app_kubernetes_io/instance="federation-api"  labels.k8s-pod/app_kubernetes_io/name="federation-api" severity=ERROR' \
    --format json --freshness "$DAYS_TO_CAPTURE"d >"$FOLDER_NAME/services/federation-api.json"
}

capture_bigquery_logs() {
  info "Capturing OperationsDashboard messages"
  bq query \
    --use_legacy_sql=false \
    --max_rows=100000 \
    --format=prettyjson \
    'SELECT
   *
 FROM
   '"$BIGQUERY_PROJECT_ID"'.sfp_data.OperationsDashboard
 WHERE
   DATE(eventTimestamp) >= DATE_SUB(CURRENT_DATE(), INTERVAL '"$DAYS_TO_CAPTURE"' DAY)
 AND
   status = "FAILED"
 ORDER BY
   stepTimestamp DESC' >"$FOLDER_NAME"/bigquery/errors.json

  info "Capturing average ingestion latencies"
  bq query \
    --use_legacy_sql=false \
    --max_rows=1000 \
    --format=sparse \
    'SELECT
    "numeric" AS table,
    DATE(eventTimestamp) AS date,
    AVG(TIMESTAMP_DIFF(ingestTimestamp, eventTimestamp, MILLISECOND)) AS latency
  FROM
    '"$BIGQUERY_PROJECT_ID"'.sfp_data.NumericDataSeries
  WHERE
   DATE(eventTimestamp) >= DATE_SUB(CURRENT_DATE(), INTERVAL '"$DAYS_TO_CAPTURE"' DAY)
  GROUP BY
    1,2
UNION ALL
SELECT
    "discrete" AS table,
    DATE(eventTimestamp) AS date,
    AVG(TIMESTAMP_DIFF(ingestTimestamp, eventTimestamp, MILLISECOND)) AS latency
  FROM
    '"$BIGQUERY_PROJECT_ID"'.sfp_data.DiscreteDataSeries
  WHERE
   DATE(eventTimestamp) >= DATE_SUB(CURRENT_DATE(), INTERVAL '"$DAYS_TO_CAPTURE"' DAY)
  GROUP BY
    1,2
  ORDER BY
    date DESC' >"$FOLDER_NAME"/bigquery/latencies.txt

  info "Capturing BigQuery InsertErrors messages"
  bq query \
    --use_legacy_sql=false \
    --max_rows=10000 \
    --format=prettyjson \
    'SELECT
   *
 FROM
   '"$BIGQUERY_PROJECT_ID"'.sfp_data.InsertErrors
 WHERE
   DATE(insertTimestamp) >= DATE_SUB(CURRENT_DATE(), INTERVAL '"$DAYS_TO_CAPTURE"' DAY)
 ORDER BY
   insertTimestamp DESC' >"$FOLDER_NAME"/bigquery/insertErrors.json
}

compress_logs() {
  info "Compressing logs"
  tar -zcf "$FOLDER_NAME.tar.gz" "$FOLDER_NAME"
  info "Logs can be found in $FOLDER_NAME.tar.gz"
}

main "${@}"
