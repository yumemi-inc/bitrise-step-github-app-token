#!/usr/bin/env bash
set -e

if [[ "$(uname)" == "Darwin" ]]; then
  base64_without_wrap="base64 -b 0"  # macOS
else
  base64_without_wrap="base64 -w 0"  # Linux, GNU
fi

if "${VERBOSE}"; then
  set -x
fi

if [ ! -f $GITHUB_APP_KEY_PATH ]; then
  echo -e "$GITHUB_APP_KEY" > $GITHUB_APP_KEY_PATH
fi

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
  installation_id=$(
    curl -s -X GET \
      -H "Authorization: Bearer ${jwt}" \
      -H "Accept: application/vnd.github.v3+json" \
      "https://api.github.com/app/installations" \
    | jq -r ".[] | .id"
  )
fi

GITHUB_APP_TOKEN=$(
  curl -s -X POST \
    -H "Authorization: Bearer ${jwt}" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/app/installations/${installation_id}/access_tokens" \
  | jq -r ".token"
)

envman add --key GITHUB_APP_TOKEN --value "${GITHUB_APP_TOKEN}"
echo "This output was GITHUB_APP_TOKEN: [REDACTED]"
