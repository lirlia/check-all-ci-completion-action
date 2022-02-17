#!/bin/bash

set -x

# function
function prefail() { echo "$@" 1>&2; exit 1; }
function output() {
    echo "::set-output name=status::$1"
    echo "::set-output name=result::$2"
}

# set default output
output "null" "null"

# validation
[[ "$DISABLE_ERREXIT" =~ ^(true|false)$ ]] ||
    prefail "disable-errexit must be set true or false  (use: ${DISABLE_ERREXIT}) "

# use specific commit hash
[[ $SPECIFIC_COMMIT_HASH ]] || SPECIFIC_COMMIT_HASH="$GITHUB_SHA"

# define error exit code if fail
ERREXIT_CODE=1
[[ $DISABLE_ERREXIT == "true" ]] && ERREXIT_CODE=0

# get this job's check suite id, because of ignore this job
echo "${{ github.token }}" | gh auth login --with-token
CHECK_SUITE_ID=$(gh api "repos/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}" | jq -r '.check_suite_id')

SECONDS=0
# loop until ci which be related to commit completed by check check-suites status
while [ $SECONDS -lt $TIMEOUT_SECONDS ]
do
    # get all ci check-suites status
    # https://docs.github.com/ja/rest/reference/checks#get-a-check-suite
    STATUS=$(gh api "repos/${GITHUB_REPOSITORY}/commits/${SPECIFIC_COMMIT_HASH}/check-suites" \
        | jq -r ".check_suites[] \
        | select(any(.app;.slug != \"codecov\")) \
        | select(any(.app;.slug != \"dependabot\")) \
        | select(any(.app;.slug != \"renovate\")) \
        | select(.id != ${CHECK_SUITE_ID}) \
        | select([.id] | inside([${IGNORE_CHECK_SUITE_IDS}]) | not ) \
        | .status" \
        | sort \
        | uniq)

    # if all statuses are completed, break
    [ "${STATUS}" = "completed" ] && break
    [[ $(( LOOP_COUNT-- )) -eq 0 ]] && output "in-progress" "null" && exit $ERREXIT_CODE
    sleep $SLEEP_SECONDS
done

# if all check-suites results are success or neutral, this ci is success
# https://docs.github.com/ja/rest/guides/getting-started-with-the-checks-api#about-check-suites
gh api "repos/${GITHUB_REPOSITORY}/commits/${SPECIFIC_COMMIT_HASH}/check-suites" \
    | jq -r ".check_suites[] \
        | select(any(.app;.slug != \"codecov\")) \
        | select(any(.app;.slug != \"dependabot\")) \
        | select(any(.app;.slug != \"renovate\")) \
        | select(.id != ${CHECK_SUITE_ID}) \
        | select([.id] | inside([${IGNORE_CHECK_SUITE_IDS}]) | not ) \
        | .conclusion" \
    | sort \
    | uniq \
    | grep -v -E "(success|neutral)" && RESULT="fail" || RESULT="success"

# output
[[ "${STATUS}" = "completed" ]] || STATUS="in-progress"
output "${STATUS}" "${RESULT}"

[[ "${RESULT}" = "success" ]] && exit 0 || exit $ERREXIT_CODE
