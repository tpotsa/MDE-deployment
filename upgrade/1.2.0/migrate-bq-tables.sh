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
  set_table_names "${@}"
  backup_current_tables "${@}"
  migrate_tables "${@}"
  create_and_update_schema_version_table "${@}"
}

check_args() {
  if [[ $# -lt 2 ]]; then
    error "Not enough arguments supplied, usage:
$NAME_PADDING migrate-bq-tables.sh PROJECT_ID DATASET_NAME"
    exit 1
  fi

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
  SCHEMAS_PATH="../deployment/config/bq-schemas/kv-json/"
  MDE_VERSION="1.2.0"

  info "***** Welcome to the MDE BigQuery Json Migration Script *****
$NAME_PADDING This script is needed to upgrade from MDE 1.1.2 to 1.2
$NAME_PADDING it will backup your MDE tables in the specified dataset
$NAME_PADDING and restore them with the fields: ${blue}payload, metadata and payloadQualifier${reset}
$NAME_PADDING migrated to the ${blue}new JSON BiqQuery Data Type.${reset}
$NAME_PADDING It will also create and additional SchemaVersion table
$NAME_PADDING to track further version changes.
$NAME_PADDING PROJECT_ID set to ${blue}${PROJECT_ID}${reset}
$NAME_PADDING DATASET_NAME set to ${blue}${DATASET_NAME}${reset}
$NAME_PADDING You're authenticated as ${blue}${USER}${reset}
$NAME_PADDING This script is intended to be run as a BigQuery Administrator."

  read -p "$NAME_PADDING Are you sure you want to continue [Y/n]? " -n 1 -r
  if [[ $REPLY =~ ^[Nn]$ ]]; then
    exit 1
  fi
  echo ""

  table_names=("NumericDataSeries" "DiscreteDataSeries" "ContinuousDataSeries" "ComponentDataSeries" "OperationsDashboard")
  existing_table_names=$(bq ls sfp_data | tail -n +3 | tr -s ' ' | cut -d' ' -f2)
  tables_exist=true
  for table_name in "${table_names[@]}"; do
    if [[ "$existing_table_names" != *"$table_name"* ]]; then
      error "Couldn't find table ${table_name} in dataset ${DATASET_NAME}"
      tables_exist=false
    fi
  done

  if [[ "$tables_exist" = false ]]; then
    error aborting
    exit 1
  fi
}

set_table_names() {
  NUMERIC_DATA_SERIES_TABLE_NAME="$PROJECT_ID:$DATASET_NAME.NumericDataSeries"
  DISCRETE_DATA_SERIES_TABLE_NAME="$PROJECT_ID:$DATASET_NAME.DiscreteDataSeries"
  CONTINUOUS_DATA_SERIES_TABLE_NAME="$PROJECT_ID:$DATASET_NAME.ContinuousDataSeries"
  COMPONENT_DATA_SERIES_TABLE_NAME="$PROJECT_ID:$DATASET_NAME.ComponentDataSeries"
  OPERATIONS_DASHBOARD_TABLE_NAME="$PROJECT_ID:$DATASET_NAME.OperationsDashboard"
  SCHEMA_VERSION_TABLE_NAME="$PROJECT_ID:$DATASET_NAME.SchemaVersion"

  NUMERIC_DATA_SERIES_TABLE_NAME_DOT="$PROJECT_ID.$DATASET_NAME.NumericDataSeries"
  DISCRETE_DATA_SERIES_TABLE_NAME_DOT="$PROJECT_ID.$DATASET_NAME.DiscreteDataSeries"
  CONTINUOUS_DATA_SERIES_TABLE_NAME_DOT="$PROJECT_ID.$DATASET_NAME.ContinuousDataSeries"
  COMPONENT_DATA_SERIES_TABLE_NAME_DOT="$PROJECT_ID.$DATASET_NAME.ComponentDataSeries"
  OPERATIONS_DASHBOARD_TABLE_NAME_DOT="$PROJECT_ID.$DATASET_NAME.OperationsDashboard"
  SCHEMA_VERSION_TABLE_NAME_DOT="$PROJECT_ID.$DATASET_NAME.SchemaVersion"

  NUMERIC_DATA_SERIES_TABLE_NAME_BACKUP="$PROJECT_ID:$DATASET_NAME.NumericDataSeriesBackup"
  DISCRETE_DATA_SERIES_TABLE_NAME_BACKUP="$PROJECT_ID:$DATASET_NAME.DiscreteDataSeriesBackup"
  CONTINUOUS_DATA_SERIES_TABLE_NAME_BACKUP="$PROJECT_ID:$DATASET_NAME.ContinuousDataSeriesBackup"
  COMPONENT_DATA_SERIES_TABLE_NAME_BACKUP="$PROJECT_ID:$DATASET_NAME.ComponentDataSeriesBackup"
  OPERATIONS_DASHBOARD_TABLE_NAME_BACKUP="$PROJECT_ID:$DATASET_NAME.OperationsDashboardBackup"
}

backup_current_tables() {
  info "Backing up tables"

  info "Backing up NumericDataSeries"
  bq cp "$NUMERIC_DATA_SERIES_TABLE_NAME" "$NUMERIC_DATA_SERIES_TABLE_NAME_BACKUP"
  bq query \
    --destination_table "$NUMERIC_DATA_SERIES_TABLE_NAME_BACKUP" \
    --replace \
    --use_legacy_sql=false \
    --max_rows=0 \
    "SELECT
   *
 FROM
   ${NUMERIC_DATA_SERIES_TABLE_NAME_DOT}
 WHERE DATE(eventTimestamp) >= \"2000-01-01\""

  info "Backing up DiscreteDataSeries"
  bq cp "$DISCRETE_DATA_SERIES_TABLE_NAME" "$DISCRETE_DATA_SERIES_TABLE_NAME_BACKUP"
  bq query \
    --destination_table "$DISCRETE_DATA_SERIES_TABLE_NAME_BACKUP" \
    --replace \
    --use_legacy_sql=false \
    --max_rows=0 \
    "SELECT
    *
  FROM
    ${DISCRETE_DATA_SERIES_TABLE_NAME_DOT}
  WHERE DATE(eventTimestamp) >= \"2000-01-01\""

  info "Backing up ContinuousDataSeries"
  bq cp "$CONTINUOUS_DATA_SERIES_TABLE_NAME" "$CONTINUOUS_DATA_SERIES_TABLE_NAME_BACKUP"
  bq query \
    --destination_table "$CONTINUOUS_DATA_SERIES_TABLE_NAME_BACKUP" \
    --replace \
    --use_legacy_sql=false \
    --max_rows=0 \
    "SELECT
      *
    FROM
      ${CONTINUOUS_DATA_SERIES_TABLE_NAME_DOT}
    WHERE DATE(eventTimestampStart) >= \"2000-01-01\""

  info "Backing up ComponentDataSeries"
  bq cp "$COMPONENT_DATA_SERIES_TABLE_NAME" "$COMPONENT_DATA_SERIES_TABLE_NAME_BACKUP"
  bq query \
    --destination_table "$COMPONENT_DATA_SERIES_TABLE_NAME_BACKUP" \
    --replace \
    --use_legacy_sql=false \
    --max_rows=0 \
    "SELECT
      *
    FROM
      ${COMPONENT_DATA_SERIES_TABLE_NAME_DOT}
    WHERE DATE(eventTimestamp) >= \"2000-01-01\""

  info "Backing up operations_dashboard"
  bq cp "$OPERATIONS_DASHBOARD_TABLE_NAME" "$OPERATIONS_DASHBOARD_TABLE_NAME_BACKUP"
  bq query \
    --destination_table "$OPERATIONS_DASHBOARD_TABLE_NAME_BACKUP" \
    --replace \
    --use_legacy_sql=false \
    --max_rows=0 \
    "SELECT
      *
  FROM
    ${OPERATIONS_DASHBOARD_TABLE_NAME_DOT}
  WHERE DATE(eventTimestamp) >= \"2000-01-01\""
}

migrate_tables() {
  info "Migrating original tables to use JSON data type"

  info "Migrating NumericDataSeries table"

  bq query \
    --destination_table "$NUMERIC_DATA_SERIES_TABLE_NAME" \
    --replace \
    --use_legacy_sql=false \
    --max_rows=0 \
    "SELECT
  * EXCEPT(payload,
    metadata,
    payloadQualifier),
  SAFE.PARSE_JSON(payload, wide_number_mode=>'round') AS payload,
  SAFE.PARSE_JSON(metadata, wide_number_mode=>'round') AS metadata,
  SAFE.PARSE_JSON(payloadQualifier, wide_number_mode=>'round') AS payloadQualifier
FROM
  ${NUMERIC_DATA_SERIES_TABLE_NAME_DOT}
WHERE DATE(eventTimestamp) >= \"2000-01-01\""

  info "Migrating DiscreteDataSeries table"

  bq query \
    --destination_table "$DISCRETE_DATA_SERIES_TABLE_NAME" \
    --replace \
    --use_legacy_sql=false \
    --max_rows=0 \
    "SELECT
  * EXCEPT(payload,
    metadata,
    payloadQualifier),
  SAFE.PARSE_JSON(payload, wide_number_mode=>'round') AS payload,
  SAFE.PARSE_JSON(metadata, wide_number_mode=>'round') AS metadata,
  SAFE.PARSE_JSON(payloadQualifier, wide_number_mode=>'round') AS payloadQualifier
FROM
  ${DISCRETE_DATA_SERIES_TABLE_NAME_DOT}
WHERE DATE(eventTimestamp) >= \"2000-01-01\""

  info "Migrating ContinuousDataSeries table"

  bq query \
    --destination_table "$CONTINUOUS_DATA_SERIES_TABLE_NAME" \
    --replace \
    --use_legacy_sql=false \
    --max_rows=0 \
    "SELECT
  * EXCEPT(payload,
    metadata,
    payloadQualifier,
    currentState,
    previousState),
  SAFE.PARSE_JSON(payload, wide_number_mode=>'round') AS payload,
  SAFE.PARSE_JSON(metadata, wide_number_mode=>'round') AS metadata,
  SAFE.PARSE_JSON(payloadQualifier, wide_number_mode=>'round') AS payloadQualifier,
  SAFE.PARSE_JSON(currentState, wide_number_mode=>'round') AS currentState,
  SAFE.PARSE_JSON(previousState, wide_number_mode=>'round') AS previousState
FROM
  ${CONTINUOUS_DATA_SERIES_TABLE_NAME_DOT}
WHERE DATE(eventTimestampStart) >= \"2000-01-01\""

  info "Migrating ComponentDataSeries table"

  bq query \
    --destination_table "$COMPONENT_DATA_SERIES_TABLE_NAME" \
    --replace \
    --use_legacy_sql=false \
    --max_rows=0 \
    "SELECT
  * EXCEPT(payload,
    metadata,
    payloadQualifier),
  SAFE.PARSE_JSON(payload, wide_number_mode=>'round') AS payload,
  SAFE.PARSE_JSON(metadata, wide_number_mode=>'round') AS metadata,
  SAFE.PARSE_JSON(payloadQualifier, wide_number_mode=>'round') AS payloadQualifier
FROM
  ${COMPONENT_DATA_SERIES_TABLE_NAME_DOT}
WHERE DATE(eventTimestamp) >= \"2000-01-01\""

  info "Migrating OperationsDashboard table"

  bq query \
    --destination_table "$OPERATIONS_DASHBOARD_TABLE_NAME" \
    --replace \
    --use_legacy_sql=false \
    --max_rows=0 \
    "SELECT
  * EXCEPT(payload),
  SAFE.PARSE_JSON(payload, wide_number_mode=>'round') AS payload
FROM
  ${OPERATIONS_DASHBOARD_TABLE_NAME_DOT}
WHERE DATE(eventTimestamp) >= \"2000-01-01\""

  info "BigQuery tables migration complete
$NAME_PADDING Original tables can be found with the name <tableName>Backup
$NAME_PADDING Delete if no longer needed"
}

create_and_update_schema_version_table() {

  info "Creating SchemaVersion table"
  bq mk --table --schema=${SCHEMAS_PATH}SchemaVersion.json \
    --label=goog-packaged-solution:"mfg-mde" \
    "$SCHEMA_VERSION_TABLE_NAME"

  info "Updating schema version information"
  bq query \
    --use_legacy_sql=false \
    --max_rows=0 \
    "INSERT \`${SCHEMA_VERSION_TABLE_NAME_DOT}\` (version)
          VALUES('${MDE_VERSION}')"
}

main "${@}"
