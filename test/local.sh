#!/usr/bin/env bash
# Exercises checkout.sh like a pols runner with a cache would, twice.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
export CACHE="${tmp}/cache" GITHUB_WORKSPACE="${tmp}/ws" GITHUB_OUTPUT="${tmp}/out"
export GITHUB_REPOSITORY="${TEST_REPO:-octocat/Hello-World}" GITHUB_SERVER_URL=https://github.com
export GITHUB_REF="${TEST_REF:-refs/heads/master}" GITHUB_SHA="${TEST_SHA:-}"
export REPOSITORY="${GITHUB_REPOSITORY}" TOKEN="${TEST_TOKEN:-}" CLEAN=true FETCH_DEPTH=1 FETCH_TAGS=false PERSIST_CREDENTIALS=true SHOW_PROGRESS=false SET_SAFE_DIRECTORY=false
mkdir -p "${CACHE}" "${GITHUB_WORKSPACE}"
[[ -n "${GITHUB_SHA}" ]] || GITHUB_SHA="$(git ls-remote "https://github.com/${GITHUB_REPOSITORY}" "${GITHUB_REF}" | cut -f1)"
export GITHUB_SHA
for p in one two; do
	CHECKOUT_PATH="${p}" REF="" bash "${here}/scripts/checkout.sh"
	[[ "$(git -C "${GITHUB_WORKSPACE}/${p}" rev-parse HEAD)" == "${GITHUB_SHA}" ]] || { echo "FAIL: ${p} not at ${GITHUB_SHA}"; exit 1; }
	[[ -s "${GITHUB_WORKSPACE}/${p}/.git/objects/info/alternates" ]] || { echo "FAIL: no alternates"; exit 1; }
	git -C "${GITHUB_WORKSPACE}/${p}" status --porcelain | grep -q . && { echo "FAIL: dirty"; exit 1; }
done
# A tag, a SHA and fetch-depth 0.
CHECKOUT_PATH=three REF="${TEST_TAG_REF:-}" FETCH_DEPTH=0 bash "${here}/scripts/checkout.sh"
git -C "${GITHUB_WORKSPACE}/three" branch -r | grep -q origin/ || { echo "FAIL: no remote branches with fetch-depth 0"; exit 1; }
CHECKOUT_PATH=four REF="${GITHUB_SHA}" bash "${here}/scripts/checkout.sh"
[[ "$(git -C "${GITHUB_WORKSPACE}/four" rev-parse HEAD)" == "${GITHUB_SHA}" ]] || { echo "FAIL: sha checkout"; exit 1; }
# Outside the workspace is refused.
if CHECKOUT_PATH=../x REF="" bash "${here}/scripts/checkout.sh" 2>/dev/null; then echo "FAIL: path outside the workspace"; exit 1; fi
cat "${GITHUB_OUTPUT}"
echo PASS
