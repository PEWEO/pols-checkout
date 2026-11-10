#!/usr/bin/env bash
# Checks a repository out from a bare mirror kept on the pols runner cache:
# the mirror fetches only what is new since the repository's last job, and
# the workspace reads its objects from the mirror (alternates), so nothing
# is copied.
#
# Environment: CACHE (the cache directory), and the action's inputs as
# REPOSITORY, REF, TOKEN, CHECKOUT_PATH, CLEAN, FETCH_DEPTH, FETCH_TAGS,
# PERSIST_CREDENTIALS, SHOW_PROGRESS, SET_SAFE_DIRECTORY, SERVER_URL.
set -euo pipefail

out="${GITHUB_OUTPUT:-/dev/stdout}"
workspace="${GITHUB_WORKSPACE:?}"
repo="${REPOSITORY:-${GITHUB_REPOSITORY:?}}"
server="${SERVER_URL:-${GITHUB_SERVER_URL:-https://github.com}}"
server="${server%/}"
url="${server}/${repo}"

if ! [[ "${repo}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
	echo "::error::repository must be owner/name, not '${repo}'"
	exit 1
fi
dest="$(realpath -m "${workspace}/${CHECKOUT_PATH:-}")"
case "${dest}/" in
"$(realpath -m "${workspace}")"/*) ;;
*)
	echo "::error::path '${CHECKOUT_PATH}' is not under the workspace ${workspace}"
	exit 1
	;;
esac

lower() { tr '[:upper:]' '[:lower:]' <<<"$1"; }
mirror="${CACHE}/git/$(lower "${repo}").git"

auth=()
basic=""
if [[ -n "${TOKEN:-}" ]]; then
	basic="$(printf 'x-access-token:%s' "${TOKEN}" | base64 | tr -d '\n')"
	echo "::add-mask::${basic}"
	auth=(-c "http.${server}/.extraheader=AUTHORIZATION: basic ${basic}")
fi
quiet=()
[[ "${SHOW_PROGRESS:-true}" == "true" ]] || quiet=(--quiet)

# The mirror: every branch and tag, kept up to date.
if ! [[ -d "${mirror}/objects" ]]; then
	echo "First checkout of ${repo} on this cache: cloning it in full once."
	mkdir -p "$(dirname "${mirror}")"
	git init -q --bare "${mirror}"
fi
git -C "${mirror}" config remote.origin.url "${url}"
git -C "${mirror}" config gc.autoDetach false

ref="${REF:-}"
sha=""
if [[ -z "${ref}" && "$(lower "${repo}")" == "$(lower "${GITHUB_REPOSITORY:-}")" ]]; then
	ref="${GITHUB_REF:-}"
	sha="${GITHUB_SHA:-}"
fi
if [[ -z "${ref}" ]]; then
	# Another repository's default branch.
	ref="$(git -C "${mirror}" "${auth[@]}" ls-remote --symref origin HEAD | awk '$1 == "ref:" { print $2; exit }')"
fi

specs=('+refs/heads/*:refs/heads/*' '+refs/tags/*:refs/tags/*')
case "${ref}" in
refs/heads/* | refs/tags/*) ;;
refs/*) specs+=("+${ref}:${ref}") ;;
esac
start=${SECONDS}
git -C "${mirror}" "${auth[@]}" fetch "${quiet[@]}" --prune --no-tags origin "${specs[@]}"

if [[ "${ref}" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]]; then
	sha="${ref}"
	ref=""
fi
if [[ -n "${sha}" ]] && ! git -C "${mirror}" cat-file -e "${sha}^{commit}" 2>/dev/null; then
	git -C "${mirror}" "${auth[@]}" fetch "${quiet[@]}" --no-tags origin "${sha}"
fi
if [[ -n "${ref}" && "${ref}" != refs/* ]]; then
	if git -C "${mirror}" rev-parse -q --verify "refs/heads/${ref}^{commit}" >/dev/null; then
		ref="refs/heads/${ref}"
	elif git -C "${mirror}" rev-parse -q --verify "refs/tags/${ref}^{commit}" >/dev/null; then
		ref="refs/tags/${ref}"
	else
		echo "::error::A branch or tag with the name '${ref}' could not be found"
		exit 1
	fi
fi
if [[ -z "${sha}" ]]; then
	sha="$(git -C "${mirror}" rev-parse --verify "${ref}^{commit}")"
fi
git -C "${mirror}" gc --auto --quiet || true
echo "Mirror of ${repo} up to date in $((SECONDS - start))s."

# The workspace.
if [[ -d "${dest}/.git" && "$(git -C "${dest}" config --get remote.origin.url || true)" == "${url}" ]]; then
	if [[ "${CLEAN:-true}" == "true" ]]; then
		git -C "${dest}" clean -ffdx
		git -C "${dest}" reset --hard --quiet HEAD || true
	fi
else
	if [[ -d "${dest}" ]]; then
		find "${dest}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
	fi
	mkdir -p "${dest}"
	git init -q "${dest}"
	git -C "${dest}" remote add origin "${url}"
fi
echo "${mirror}/objects" >"${dest}/.git/objects/info/alternates"
if [[ "${SET_SAFE_DIRECTORY:-true}" == "true" ]]; then
	git config --global --add safe.directory "${dest}"
fi

case "${ref}" in
refs/heads/*)
	branch="${ref#refs/heads/}"
	git -C "${dest}" update-ref "refs/remotes/origin/${branch}" "${sha}"
	git -C "${dest}" checkout --force -q -B "${branch}" "refs/remotes/origin/${branch}"
	;;
refs/tags/*)
	git -C "${dest}" update-ref "${ref}" "$(git -C "${mirror}" rev-parse "${ref}")"
	git -C "${dest}" checkout --force -q --detach "${ref}"
	;;
refs/pull/*)
	git -C "${dest}" update-ref "refs/remotes/pull/${ref#refs/pull/}" "${sha}"
	git -C "${dest}" checkout --force -q --detach "${sha}"
	;;
*)
	git -C "${dest}" checkout --force -q --detach "${sha}"
	;;
esac

# The history and tags the workspace sees: all of it with fetch-depth 0 or
# fetch-tags, as actions/checkout gives (read from the mirror, no network).
local_specs=()
[[ "${FETCH_DEPTH:-1}" == "0" ]] && local_specs+=('+refs/heads/*:refs/remotes/origin/*' '+refs/tags/*:refs/tags/*')
[[ "${FETCH_TAGS:-false}" == "true" && "${FETCH_DEPTH:-1}" != "0" ]] && local_specs+=('+refs/tags/*:refs/tags/*')
if ((${#local_specs[@]} > 0)); then
	git -C "${dest}" fetch --quiet --no-tags "${mirror}" "${local_specs[@]}"
fi

if [[ "${PERSIST_CREDENTIALS:-true}" == "true" && -n "${basic}" ]]; then
	git -C "${dest}" config --local "http.${server}/.extraheader" "AUTHORIZATION: basic ${basic}"
fi

{
	echo "ref=${ref}"
	echo "commit=${sha}"
} >>"${out}"
echo "Checked out ${repo} ${ref:-${sha}} at ${sha} in $((SECONDS - start))s."
