#!/usr/bin/env bash
set -e -o pipefail

readonly WORK_DIR=$(mktemp -d)

function raise() {
  echo $1 1>&2
  return 1
}
err_buf=""
function err() {
  # Usage: trap 'err ${LINENO[0]} ${FUNCNAME[1]}' ERR
  status=$?
  lineno=$1
  func_name=${2:-main}
  err_str="ERROR: [`date +'%Y-%m-%d %H:%M:%S'`] ${SCRIPT}:${func_name}() returned non-zero exit status ${status} at line ${lineno}"
  echo ${err_str}
  err_buf+=${err_str}
}
function finally() {
  rm -rf ${WORK_DIR}
}

trap 'err ${LINENO[0]} ${FUNCNAME[1]}' ERR
trap finally EXIT

if [ -z "$GITHUB_APP_ID" ]; then
  echo "GITHUB_APP_ID is empty.: $GITHUB_APP_ID"
  exit 1
fi

if [ ! -f $GITHUB_APP_KEY_PATH ]; then
  if [ -z "$GITHUB_APP_KEY" ]; then
    echo "GITHUB_APP_KEY is empty or GITHUB_APP_KEY_PATH does not exist.: $GITHUB_APP_KEY_PATH"
    exit 1
  fi
  echo -e "$GITHUB_APP_KEY" > $GITHUB_APP_KEY_PATH
fi

if [[ "$(uname)" == "Darwin" ]]; then
  base64_without_wrap="base64 -b 0"  # macOS
else
  base64_without_wrap="base64 -w 0"  # Linux, GNU
fi

if "${VERBOSE}"; then
  set -x
fi

mkdir -p ${WORK_DIR}

header=$(echo -n '{"alg":"RS256","typ":"JWT"}' | $base64_without_wrap)

now=$(date "+%s")
iat=$((${now} - 60))
exp=$((${now} + (10 * 60)))
payload=$(echo -n "{\"iat\":${iat},\"exp\":${exp},\"iss\":${GITHUB_APP_ID}}" | $base64_without_wrap)

unsigned_token="${header}.${payload}"
signed_token=$(echo -n "${unsigned_token}" | openssl dgst -binary -sha256 -sign "${GITHUB_APP_KEY_PATH}" | base64)

jwt="${unsigned_token}.${signed_token}"

installation_id=$GITHUB_APP_INSTALLATION
if [ -z "$installation_id" ]; then
  installations=$(
    curl -s -X GET \
      -H "Authorization: Bearer ${jwt}" \
      -H "Accept: application/vnd.github.v3+json" \
      "https://api.github.com/app/installations")
  installation_id=`echo $installations | jq -r ".[] | .id?"`
  if [ "$installation_id" = "null" ]; then
    raise "Failed to fetch installation_id: $(<$installations)"
  fi
fi

access_tokens=$(
  curl -s -X POST \
    -H "Authorization: Bearer ${jwt}" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/app/installations/${installation_id}/access_tokens")
github_app_token=`echo $access_tokens | jq -r ".token?"`

if [ "$github_app_token" = "null" ]; then
  raise "Failed to fetch github_app_token: $(<$github_app_token)"
fi

envman add --key GITHUB_APP_TOKEN --value "${github_app_token}"
