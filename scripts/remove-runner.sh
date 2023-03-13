#!/bin/bash

## required
GITHUB_TOKEN="${GITHUB_TOKEN}"
GITHUB_RUNNER_NAME="${GITHUB_RUNNER_NAME}"

## default
WORKING_DIRECTORY="${WORKING_DIRECTORY:=$PWD}"
GITHUB_ORGANIZATION="${RUNNER_ORGANIZATION:-sourcefuse}"
GITHUB_RUNNER_ID_OUT="${RUNNER_ID_OUT_PATH:=$WORKING_DIRECTORY/runner-id}"

set -e
curl -H "Accept: application/vnd.github.v3+json" \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  https://api.github.com/orgs/${GITHUB_ORGANIZATION}/actions/runners > "${WORKING_DIRECTORY}/registered-runners.json"

jq -r ".runners[] | select (.name == \"${GITHUB_RUNNER_NAME}\" ).id" "${WORKING_DIRECTORY}/registered-runners.json" > ${GITHUB_RUNNER_ID_OUT} 2>$WORKING_DIRECTORY/errors.log

if [ -s "${GITHUB_RUNNER_ID_OUT}" ]; then
  runner_id=$(cat "${GITHUB_RUNNER_ID_OUT}")
  printf "\nRemoving ${GITHUB_RUNNER_NAME}...\n"
  curl -X DELETE -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    https://api.github.com/orgs/${GITHUB_ORGANIZATION}/actions/runners/${runner_id}
  printf "/n${GITHUB_RUNNER_NAME} successfully removed!\n"
else
  printf "/n${GITHUB_RUNNER_NAME} already removed!\n"
fi
