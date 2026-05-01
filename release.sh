#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Bucky"
REMOTE="${REMOTE:-origin}"
INFO_PLIST="packaging/Info.plist"
APP_PATH="build/${APP_NAME}.app"
EXECUTABLE_PATH="${APP_PATH}/Contents/MacOS/${APP_NAME}"
API_ROOT="${GITHUB_API_URL:-https://api.github.com}"
API_VERSION="2022-11-28"
DRY_RUN=0
CREATED_DRAFT_RELEASE_ID=""
RELEASE_PUBLISHED=0

usage() {
    cat <<USAGE
Usage: ./release.sh [--dry-run]

Creates a signed git tag for the current plist semantic version, pushes it,
creates a GitHub release with generated release notes, and uploads the package
zip plus SHA-256 checksum from ./package.sh.

Required:
  - GITHUB_TOKEN with repository Contents: write permission
  - git tag signing configured for 'git tag -s'
  - curl
  - python3

Environment:
  REMOTE          Git remote to release from. Default: origin
  DEFAULT_BRANCH Default branch override if origin/HEAD is unavailable.
  GITHUB_API_URL GitHub API root. Default: https://api.github.com
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=1
elif [[ $# -gt 0 ]]; then
    usage >&2
    exit 2
fi

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "error: required command '$1' was not found" >&2
        exit 1
    fi
}

require_command curl
require_command git
require_command lipo
require_command python3
require_command shasum

api_curl() {
    curl --fail-with-body -L \
        --silent \
        --show-error \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${GITHUB_TOKEN}" \
        -H "X-GitHub-Api-Version: ${API_VERSION}" \
        "$@"
}

cleanup_draft_release() {
    if [[ -n "${CREATED_DRAFT_RELEASE_ID}" && "${RELEASE_PUBLISHED}" -eq 0 ]]; then
        echo "Cleaning up unpublished draft release ${CREATED_DRAFT_RELEASE_ID}..." >&2
        api_curl \
            -X DELETE \
            "${API_ROOT}/repos/${OWNER}/${REPO}/releases/${CREATED_DRAFT_RELEASE_ID}" >/dev/null || true
    fi
}

trap cleanup_draft_release EXIT

if [[ ! -f "${INFO_PLIST}" ]]; then
    echo "error: ${INFO_PLIST} does not exist" >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}")"
if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.+][0-9A-Za-z.-]+)?$ ]]; then
    echo "error: plist version '${VERSION}' is not a semantic version" >&2
    exit 1
fi

TAG_NAME="v${VERSION}"
RELEASE_NAME="${APP_NAME} ${VERSION}"

remote_url="$(git remote get-url "${REMOTE}")"
repo_slug="$(python3 - "${remote_url}" <<'PY'
import re
import sys

url = sys.argv[1].strip()
patterns = [
    r"^git@github\.com:(?P<slug>[^/]+/[^/]+?)(?:\.git)?$",
    r"^https://github\.com/(?P<slug>[^/]+/[^/]+?)(?:\.git)?$",
    r"^ssh://git@github\.com/(?P<slug>[^/]+/[^/]+?)(?:\.git)?$",
]

for pattern in patterns:
    match = re.match(pattern, url)
    if match:
        print(match.group("slug"))
        sys.exit(0)

sys.exit(1)
PY
)" || {
    echo "error: could not derive GitHub owner/repo from ${REMOTE} URL: ${remote_url}" >&2
    exit 1
}

OWNER="${repo_slug%%/*}"
REPO="${repo_slug#*/}"

default_branch="${DEFAULT_BRANCH:-}"
if [[ -z "${default_branch}" ]]; then
    default_ref="$(git symbolic-ref --quiet --short "refs/remotes/${REMOTE}/HEAD" 2>/dev/null || true)"
    default_branch="${default_ref#${REMOTE}/}"
fi
if [[ -z "${default_branch}" || "${default_branch}" == "${default_ref:-}" ]]; then
    default_branch="main"
fi

current_branch="$(git branch --show-current)"
if [[ "${current_branch}" != "${default_branch}" ]]; then
    echo "error: current branch is '${current_branch}', expected default branch '${default_branch}'" >&2
    exit 1
fi

if [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
    echo "error: worktree has uncommitted changes; release from a clean default branch" >&2
    exit 1
fi

if [[ -z "${GITHUB_TOKEN:-}" && "${DRY_RUN}" -eq 0 ]]; then
    echo "error: GITHUB_TOKEN is required to create the GitHub release and upload assets" >&2
    exit 1
fi

echo "Fetching ${REMOTE}/${default_branch} and tags..."
git fetch "${REMOTE}" "+refs/heads/${default_branch}:refs/remotes/${REMOTE}/${default_branch}" --tags

remote_head="$(git rev-parse "${REMOTE}/${default_branch}")"
local_head="$(git rev-parse HEAD)"
if [[ "${local_head}" != "${remote_head}" ]]; then
    echo "error: HEAD is not ${REMOTE}/${default_branch}" >&2
    exit 1
fi
release_ref="${REMOTE}/${default_branch}"
release_commit="${remote_head}"

LOCAL_TAG_EXISTS=0
REMOTE_TAG_EXISTS=0
LOCAL_TAG_CREATED=0

if git rev-parse --verify --quiet "refs/tags/${TAG_NAME}" >/dev/null; then
    tag_head="$(git rev-list -n 1 "${TAG_NAME}")"
    if [[ "${tag_head}" != "${release_commit}" ]]; then
        echo "error: local tag ${TAG_NAME} already exists but does not point to ${release_ref}" >&2
        exit 1
    fi
    LOCAL_TAG_EXISTS=1
fi

remote_tag_head="$(git ls-remote --tags "${REMOTE}" "refs/tags/${TAG_NAME}" | awk 'NR == 1 { print $1 }')"
if [[ -n "${remote_tag_head}" ]]; then
    remote_tag_commit="$(git rev-list -n 1 "${remote_tag_head}")"
    if [[ "${remote_tag_commit}" != "${release_commit}" ]]; then
        echo "error: remote tag ${TAG_NAME} already exists but does not point to ${release_ref}" >&2
        exit 1
    fi
    REMOTE_TAG_EXISTS=1
fi

if [[ "${DRY_RUN}" -eq 0 ]]; then
    if [[ "${LOCAL_TAG_EXISTS}" -eq 0 ]]; then
        echo "Creating signed tag ${TAG_NAME} at ${release_ref}..."
        git tag -s "${TAG_NAME}" -m "${RELEASE_NAME}" "${release_ref}"
        git tag -v "${TAG_NAME}" >/dev/null
        LOCAL_TAG_CREATED=1
    else
        echo "Using existing local tag ${TAG_NAME} at ${release_ref}."
    fi

    if [[ "${REMOTE_TAG_EXISTS}" -eq 0 ]]; then
        echo "Pushing tag ${TAG_NAME}..."
        if ! git push "${REMOTE}" "${TAG_NAME}"; then
            if [[ "${LOCAL_TAG_CREATED}" -eq 1 ]]; then
                git tag -d "${TAG_NAME}" >/dev/null
            fi
            echo "error: failed to push ${TAG_NAME}; repository rules may restrict tag creation." >&2
            echo "Allow this release actor to create refs/tags/${TAG_NAME}, then rerun." >&2
            exit 1
        fi
    else
        echo "Using existing remote tag ${TAG_NAME} at ${release_ref}."
    fi

    remote_tag_head="$(git ls-remote --tags "${REMOTE}" "refs/tags/${TAG_NAME}" | awk 'NR == 1 { print $1 }')"
    if [[ -z "${remote_tag_head}" ]]; then
        echo "error: remote tag ${TAG_NAME} does not exist; refusing to create a release that would need GitHub to create it during publish." >&2
        exit 1
    fi
fi

if [[ "${DRY_RUN}" -eq 0 ]] && api_curl "${API_ROOT}/repos/${OWNER}/${REPO}/releases/tags/${TAG_NAME}" >/tmp/bucky-existing-release.json 2>/dev/null; then
    existing_release_url="$(python3 -c 'import json, sys; print(json.load(sys.stdin)["html_url"])' </tmp/bucky-existing-release.json)"
    echo "error: release ${TAG_NAME} already exists: ${existing_release_url}" >&2
    echo "If immutable releases are enabled and this release was published without assets, bump the plist version and release a new tag." >&2
    exit 1
fi

echo "Packaging ${APP_NAME} ${VERSION}..."
./package.sh

if [[ ! -x "${EXECUTABLE_PATH}" ]]; then
    echo "error: ${EXECUTABLE_PATH} does not exist or is not executable after packaging" >&2
    exit 1
fi

ARCHS="$(lipo -archs "${EXECUTABLE_PATH}")"
ARCH_LABEL="${ARCHS// /-}"
ZIP_PATH="dist/${APP_NAME}-${VERSION}-macos-${ARCH_LABEL}.zip"
SHA_PATH="${ZIP_PATH}.sha256"

if [[ ! -f "${ZIP_PATH}" || ! -f "${SHA_PATH}" ]]; then
    echo "error: expected package assets were not created: ${ZIP_PATH} and ${SHA_PATH}" >&2
    exit 1
fi

echo "Verifying package checksum..."
shasum -a 256 -c "${SHA_PATH}"

if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "Dry run complete:"
    echo "  tag: ${TAG_NAME}"
    echo "  repo: ${OWNER}/${REPO}"
    echo "  assets:"
    echo "    ${ZIP_PATH}"
    echo "    ${SHA_PATH}"
    exit 0
fi

release_payload="$(python3 - "${TAG_NAME}" "${RELEASE_NAME}" <<'PY'
import json
import sys

tag_name = sys.argv[1]
release_name = sys.argv[2]
print(json.dumps({
    "tag_name": tag_name,
    "name": release_name,
    "draft": True,
    "prerelease": False,
    "generate_release_notes": True,
}))
PY
)"

echo "Creating draft GitHub release ${TAG_NAME}..."
release_response="$(api_curl \
    -X POST \
    -H "Content-Type: application/json" \
    "${API_ROOT}/repos/${OWNER}/${REPO}/releases" \
    -d "${release_payload}")"

CREATED_DRAFT_RELEASE_ID="$(python3 -c 'import json, sys; print(json.load(sys.stdin)["id"])' <<<"${release_response}")"
upload_url="$(python3 -c 'import json, sys; print(json.load(sys.stdin)["upload_url"].split("{", 1)[0])' <<<"${release_response}")"

upload_asset() {
    local path="$1"
    local content_type="$2"
    local name
    local encoded_name

    name="$(basename "${path}")"
    encoded_name="$(python3 - "${name}" <<'PY'
import sys
import urllib.parse

print(urllib.parse.quote(sys.argv[1]))
PY
)"

    echo "Uploading ${name}..."
    api_curl \
        -X POST \
        -H "Content-Type: ${content_type}" \
        --data-binary @"${path}" \
        "${upload_url}?name=${encoded_name}" >/dev/null
}

upload_asset "${ZIP_PATH}" "application/zip"
upload_asset "${SHA_PATH}" "text/plain"

publish_payload="$(python3 - <<'PY'
import json

print(json.dumps({
    "draft": False,
}))
PY
)"

echo "Publishing GitHub release ${TAG_NAME}..."
api_curl \
    -X PATCH \
    -H "Content-Type: application/json" \
    "${API_ROOT}/repos/${OWNER}/${REPO}/releases/${CREATED_DRAFT_RELEASE_ID}" \
    -d "${publish_payload}"
RELEASE_PUBLISHED=1

echo "Released ${TAG_NAME}: https://github.com/${OWNER}/${REPO}/releases/tag/${TAG_NAME}"
