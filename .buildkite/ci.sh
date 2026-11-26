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
