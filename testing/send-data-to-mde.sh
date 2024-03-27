#!/usr/bin/env bash
# Copyright 2023 Google LLC
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
$NAME_PADDING send-data-to-mde.sh PROJECT_ID TYPE"
  exit 1
fi

NUMERIC_TYPE="numeric"
DISCRETE_TYPE="discrete"

main() {
    check_args "${@}"

    echo "Sending messages every 5 seconds"
    echo "Press [CTRL+C] to stop"

    PROJECT_ID=${1}
    
    while :
    do    
        TIMESTAMP=$(($(date +%s000)))
        
        if [ "$TYPE" = "$NUMERIC_TYPE" ]; then
            JSON_STRING=$( jq -n '{ "tagName": "mde-test-numeric", "timestamp": "'$TIMESTAMP'", "value": 10.0 }' )
        elif [ "$TYPE" = "$DISCRETE_TYPE" ]; then 
            JSON_STRING=$( jq -n '{ "tagName": "mde-test-discrete", "timestamp": "'$TIMESTAMP'", "value": { "test1": true, "test2": "someValue"} }' )
        fi
        
        echo "Sent:"
        echo "${JSON_STRING}" | jq '.'
        
        gcloud pubsub topics publish projects/${PROJECT_ID}/topics/input-messages --message="$JSON_STRING"
        echo "Sleeping for 5 sec..."
        sleep 5
    done
    # echo "Sending test message"
    # TIMESTAMP=$(date +%s%3N)
    # echo "Timestamp: ${TIMESTAMP}"
    # JSON_STRING=$( jq -n "{tagName: \"deployment-test-numeric\", timestamp: ${TIMESTAMP}, value: 10.0}" )
    # echo "Message: ${JSON_STRING}"

    # export PROJECT_ID=$(gcloud config get-value project)
    # gcloud pubsub topics publish projects/${PROJECT_ID}/topics/input-messages --message="$JSON_STRING"

    # echo "Done sending. Sleeping for 20 sec..."
    # sleep 20
}

check_args() {

  if [[ -z "$1" ]]; then
    error "Project ID can not be empty"
    exit 1
  fi

  if [[ -z "$2" ]]; then
    error "Type can not be empty - use either 'numeric' or 'discrete'"
    exit 1
  fi

  if [ "$2" != "$NUMERIC_TYPE" ] && [ "$2" != "$DISCRETE_TYPE" ] ; then
     error "Type can be - either 'numeric' or 'discrete'"
    exit 1
  fi


  if ! command -v gcloud &>/dev/null; then
    error "gcloud is required to run this script"
    exit 1
  fi

  if ! command -v jq &>/dev/null; then
    error "jq is required to run this script"
    exit 1
  fi

  PROJECT_ID=${1}
  TYPE=${2}
  USER=$(gcloud config get-value account 2>/dev/null)

  info "***** Welcome to the MDE Data Generator 1.3 *****
$NAME_PADDING This script will send ${TYPE} data to MDE so that you can validate that the entire pipeline is working${reset}
$NAME_PADDING PROJECT_ID set to ${blue}${PROJECT_ID}${reset}
$NAME_PADDING You're authenticated as ${blue}${USER}${reset}"

  read -p "$NAME_PADDING Do you want to start sending data [Y/n]? " -n 1 -r
  if [[ $REPLY =~ ^[Nn]$ ]]; then
    exit 1
  fi
  echo ""
}

main "${@}"