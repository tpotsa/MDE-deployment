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

main() {
  check_args "${@}"
  migrate_files "${@}"
}

check_args() {
  if [[ $# -lt 1 ]]; then
    error "Not enough arguments supplied, usage:
$NAME_PADDING migrate-gcs-data.sh PROJECT_ID"
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

  if ! command -v gsutil &>/dev/null; then
    error "gsutil is required to run this script"
    exit 1
  fi

  PROJECT_ID=${1}
  GCS_WRITER_BUCKET="gs://${PROJECT_ID}-gcs-ingestion"
  USER=$(gcloud config get-value account 2>/dev/null)

  info "***** Welcome to the MDE GCS Writer migration Script *****
$NAME_PADDING This script is needed to upgrade from MDE 1.1.2 to 1.2
$NAME_PADDING it will move all the gcs-writer files to a V1 subfolder
$NAME_PADDING to help when/if schema changes are implemented in future versions of MDE.
$NAME_PADDING PROJECT_ID set to ${blue}${PROJECT_ID}${reset}
$NAME_PADDING GCS WRITER BUCKET set to ${blue}${GCS_WRITER_BUCKET}${reset}
$NAME_PADDING You're authenticated as ${blue}${USER}${reset}
$NAME_PADDING This script is intended to be run as a GCS Administrator."

  read -p "$NAME_PADDING Are you sure you want to continue [Y/n]? " -n 1 -r
  if [[ $REPLY =~ ^[Nn]$ ]]; then
    exit 1
  fi
  echo ""
}

migrate_files() {
  info "Checking for existing files in ${GCS_WRITER_BUCKET}"

  files_exist=$(gsutil -q stat "${GCS_WRITER_BUCKET}/gcsoutput*" || echo 1)

  if [[ ${files_exist} != 1 ]]; then
    info "Migrating GCS files to V1 subfolder."
    info "Be patient since this might take some time."
    gsutil -m mv "${GCS_WRITER_BUCKET}/gcsoutput*" "${GCS_WRITER_BUCKET}/v1/"
  else
    info "No files in ${GCS_WRITER_BUCKET} bucket, no migration necessary."
  fi
  info "GCS files migration complete"
}

main "${@}"
