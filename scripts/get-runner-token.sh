#!/bin/bash

## required
GITHUB_TOKEN="${GITHUB_TOKEN}"
AWS_REGION="${AWS_REGION:=us-east-1}"

## default
REPOS_OR_ORGS="${REPOS_OR_ORGS:=orgs}"
NAMESPACE="${NAMESPACE:-arc}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
WORKING_DIRECTORY="${WORKING_DIRECTORY:=$PWD}"
GITHUB_OWNER="${GITHUB_OWNER:-sourcefuse}"

set -e

## get the token from github (using PAT)
runner_token=$(curl -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/${REPOS_OR_ORGS}/${GITHUB_OWNER}/actions/runners/registration-token" | jq -r .token)

## put the token in ssm
aws ssm put-parameter \
    --region $AWS_REGION \
    --name "/${NAMESPACE}/${ENVIRONMENT}/github-runner/token" \
    --value "${runner_token}" \
    --type SecureString \
    --overwrite > /dev/null

printf "\nSSM Parameter value added for the runner token: /${NAMESPACE}/${ENVIRONMENT}/github-runner/token\n"
