#!/usr/bin/env bash
set -e

if "${VERBOSE}"; then
  set -x
fi

if [ ! -f $GITHUB_APP_KEY_PATH ]; then
    echo -e "$GITHUB_APP_KEY" > $GITHUB_APP_KEY_PATH
fi

header=$(echo -n '{"alg":"RS256","typ":"JWT"}' | base64 -b 0)

now=$(date "+%s")
iat=$((${now} - 60))
exp=$((${now} + (10 * 60)))
payload=$(echo -n "{\"iat\":${iat},\"exp\":${exp},\"iss\":${GITHUB_APP_ID}}" | base64 -b 0)

unsigned_token="${header}.${payload}"
signed_token=$(echo -n "${unsigned_token}" | openssl dgst -binary -sha256 -sign "${GITHUB_APP_KEY_PATH}" | base64)

jwt="${unsigned_token}.${signed_token}"

installation_id=$(
  curl -s -X GET \
    -H "Authorization: Bearer ${jwt}" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/app/installations" \
  | jq -r ".[] | .id"
)

installation_token=$(
  curl -s -X POST \
    -H "Authorization: Bearer ${jwt}" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/app/installations/${installation_id}/access_tokens" \
  | jq -r ".token"
)

envman add --key GITHUB_APP_TOKEN --value "${installation_token}"
