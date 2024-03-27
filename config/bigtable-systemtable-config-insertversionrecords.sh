#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Not enough argument supplied, usage should be like:"
  echo "bootstrap-timeseries-internal-config.sh PROJECT_ID"
  exit 1
fi

if [[ -z "$1" ]]; then
  echo "None of the arguments can be empty"
  exit 1
fi
if [[ -z "$2" ]]; then
  echo "None of the arguments can be empty"
  exit 1
fi

PROJECT_ID=${1}
BT_INSTANCE_ID=${2}
CONFIG_TABLE_NAME=mde-internal-config
APP_PROFILE=fed-api
MDE_VERSION="1.3.0"
COLUMN_FAMILIES=("compatibility")
COLUMN_QUALIFIERS=("version")


echo "Inserting config row btschema"
rowkey="btschema"

  echo "Using RowKey = ${rowkey}"
  cbt -project "${PROJECT_ID}" -instance "${BT_INSTANCE_ID}" set "${CONFIG_TABLE_NAME}" "${rowkey}" "${COLUMN_FAMILIES[0]}":"${COLUMN_QUALIFIERS[0]}"="1.3.0"

  echo "Reading last row from BT"
  cbt -project "${PROJECT_ID}" -instance "${BT_INSTANCE_ID}" read "${CONFIG_TABLE_NAME}" start="${rowkey}" count=1

echo "Inserting config row configmanager"
rowkey="configmanager"

  echo "Using RowKey = ${rowkey}"
  cbt -project "${PROJECT_ID}" -instance "${BT_INSTANCE_ID}" set "${CONFIG_TABLE_NAME}" "${rowkey}" "${COLUMN_FAMILIES[0]}":"${COLUMN_QUALIFIERS[0]}"="1.3.0"

  echo "Reading last row from BT"
  cbt -project "${PROJECT_ID}" -instance "${BT_INSTANCE_ID}" read "${CONFIG_TABLE_NAME}" start="${rowkey}" count=1

