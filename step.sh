#!/usr/bin/env bash
set -e

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

if [ -z "${github_app_id}" ]; then
  echo "github_app_id is empty.: ${github_app_id}"
  exit 1
fi

if [ ! -f ${github_app_key_path} ]; then
  if [ -z "${github_app_key}" ]; then
    echo "github_app_key is empty or github_app_key_path does not exist.: ${github_app_key_path}"
    exit 1
  fi
  github_app_key_path="${WORK_DIR}/private-key.pem"
  echo -e "${github_app_key}" > ${github_app_key_path}
fi

if [[ "$(uname)" == "Darwin" ]]; then
  base64_without_wrap="base64 -b 0"  # macOS
else
  base64_without_wrap="base64 -w 0"  # Linux, GNU
fi

if "${verbose}"; then
  set -x
fi

mkdir -p ${WORK_DIR}

header=$(echo -n '{"alg":"RS256","typ":"JWT"}' | ${base64_without_wrap})

now=$(date "+%s")
iat=$((${now} - 60))
exp=$((${now} + (10 * 60)))
payload=$(echo -n "{\"iat\":${iat},\"exp\":${exp},\"iss\":${github_app_id}}" | ${base64_without_wrap})

unsigned_token="${header}.${payload}"
signed_token=$(echo -n "${unsigned_token}" | openssl dgst -binary -sha256 -sign "${github_app_key_path}" | ${base64_without_wrap})

jwt="${unsigned_token}.${signed_token}"

installation_id=${github_app_installation}
if [ -z "${installation_id}" ]; then
  installation_id=$(
    curl -f -s -X GET \
      -H "Authorization: Bearer ${jwt}" \
      -H "Accept: application/vnd.github.v3+json" \
      "https://api.github.com/app/installations" \
    | jq -r ".[] | .id?")
  if [ "${installation_id}" = "" ]; then
    raise "Failed to fetch installation_id"
  fi
fi

github_app_token=$(
  curl -f -s -X POST \
    -H "Authorization: Bearer ${jwt}" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/app/installations/${installation_id}/access_tokens" \
  | jq -r ".token?")
if [ "${github_app_token}" = "" ]; then
  raise "Failed to fetch github_app_token"
fi

envman add --key GITHUB_APP_TOKEN --value "${github_app_token}"
