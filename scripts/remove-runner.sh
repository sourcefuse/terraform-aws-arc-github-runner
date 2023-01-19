#!/bin/bash

## required
GITHUB_RUNNER_TOKEN="${GITHUB_RUNNER_TOKEN}"
GITHUB_RUNNER_NAME="${GITHUB_RUNNER_NAME}"

## default
WORKING_DIRECTORY="${WORKING_DIRECTORY:=$PWD}"
GITHUB_RUNNER_ORGANIZATION="${RUNNER_ORGANIZATION:-sourcefuse}"
GITHUB_RUNNER_ID_OUT_PATH="${RUNNER_ID_OUT_PATH:=$WORKING_DIRECTORY/runner-id}"

set -e
curl -H "Accept: application/vnd.github.v3+json" \
  -H "Authorization: Bearer ${GITHUB_RUNNER_TOKEN}" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  https://api.github.com/orgs/${GITHUB_RUNNER_ORGANIZATION}/actions/runners > registered-runners.json


jq -r ".runners[] | select (.name == \"${GITHUB_RUNNER_NAME}\" ).id" ./registered-runners.json > ${GITHUB_RUNNER_ID_OUT_PATH}

if [ -s "${GITHUB_RUNNER_ID_OUT_PATH}" ]; then
  runner_id=$(cat "${GITHUB_RUNNER_ID_OUT_PATH}")
  curl -X DELETE -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${GITHUB_RUNNER_TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    https://api.github.com/orgs/${GITHUB_RUNNER_ORGANIZATION}/actions/runners/${runner_id}
else
  :
fi
