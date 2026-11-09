#!/usr/bin/env bash
# Decide whether the Swift 6 header fix needs CI, and fast-forward the
# maintenance branch onto a new stable upstream tag when the patch still applies.
set -euo pipefail

if [[ "${CI:-}" != "true" && "${SWIFT6_DECIDE_ALLOW_LOCAL:-}" != "1" ]]; then
    echo "decide.sh runs in GitHub Actions. Set SWIFT6_DECIDE_ALLOW_LOCAL=1 to dry-run locally." >&2
    exit 1
fi

branch="fix/swift6-strict-concurrency"
upstream_url="https://github.com/zxing-cpp/zxing-cpp.git"
event_name="${EVENT_NAME:?EVENT_NAME is required}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
runtime="$(mktemp -d)"
cp "$script_dir/apply.sh" "$script_dir/0001-exclude-private-ios-headers.patch" "$runtime/"
input_ref="${INPUT_UPSTREAM_REF:-}"
input_publish="${INPUT_PUBLISH:-}"
dry_run="${DRY_RUN:-}"
output_file="${GITHUB_OUTPUT:-}"

set_output() {
    if [[ -n "$output_file" ]]; then
        printf '%s=%s\n' "$1" "$2" >> "$output_file"
    else
        printf '%s=%s\n' "$1" "$2"
    fi
}

write_summary() {
    if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
        printf '%s\n' "$1" >> "$GITHUB_STEP_SUMMARY"
    fi
    printf '%s\n' "$1"
}

if git remote get-url upstream >/dev/null 2>&1; then
    git remote set-url upstream "$upstream_url"
else
    git remote add upstream "$upstream_url"
fi

git fetch upstream --tags --prune --force
git fetch origin --tags --prune --force

latest_stable_tag() {
    git for-each-ref --format='%(refname:short)' 'refs/tags/v*' \
        | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
        | sort -V \
        | tail -n 1
}

resolve_upstream() {
    local ref="$1"
    if [[ "$ref" =~ ^[0-9a-fA-F]{40}$ ]]; then
        git fetch upstream "$ref"
        git rev-parse "${ref}^{commit}"
    elif [[ "$ref" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-rc[0-9]+)?$ ]]; then
        git fetch upstream "refs/tags/${ref}:refs/tags/${ref}"
        git rev-parse "${ref}^{commit}"
    else
        echo "upstream ref must be a full SHA or a vX.Y.Z / vX.Y.Z-rcN tag." >&2
        exit 1
    fi
}

modulemap_is_fixed() {
    local modulemap="$1"
    local header
    [[ -f "$modulemap" ]] || return 1
    for header in "Reader/ZXIPosition+Helper.h" "ZXIFormatHelper.h" "Version.h"; do
        grep -F -q "exclude header \"$header\"" "$modulemap" || return 1
    done
}

finish_check_only() {
    local upstream_tag="$1"
    local upstream_sha="$2"
    local release_tag="$3"
    local candidate_sha="$4"
    local verify_fork="$5"
    local verify_replay="$6"
    local compare_modulemap="$7"
    set_output proceed_release false
    set_output verify_fork "$verify_fork"
    set_output verify_replay "$verify_replay"
    set_output compare_modulemap "$compare_modulemap"
    set_output upstream_tag "$upstream_tag"
    set_output upstream_sha "$upstream_sha"
    set_output release_tag "$release_tag"
    set_output candidate_sha "$candidate_sha"
}

if [[ -n "$input_ref" ]]; then
    if [[ "$event_name" != "workflow_dispatch" ]]; then
        echo "upstream_ref is only accepted from workflow_dispatch." >&2
        exit 1
    fi
    upstream_sha="$(resolve_upstream "$input_ref")"
    if [[ "$input_ref" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-rc[0-9]+)?$ ]]; then
        upstream_tag="$input_ref"
    else
        upstream_tag="commit"
    fi
    write_summary "Compatibility check for \`${input_ref}\` (${upstream_sha}). The maintenance branch and Fixed tags stay unchanged."
    finish_check_only "$upstream_tag" "$upstream_sha" "" "" false true false
    exit 0
fi

upstream_tag="$(latest_stable_tag)"
if [[ -z "$upstream_tag" ]]; then
    echo "No stable upstream tag matched vX.Y.Z." >&2
    exit 1
fi
upstream_sha="$(git rev-parse "${upstream_tag}^{commit}")"
release_tag="${upstream_tag}-Fixed"

publish=false
if [[ "$event_name" == "schedule" ]]; then
    publish=true
elif [[ "$event_name" == "workflow_dispatch" && "$input_publish" == "true" ]]; then
    publish=true
fi

if [[ "$event_name" == "push" || "$event_name" == "pull_request" ]]; then
    candidate_sha="$(git rev-parse HEAD)"
    verify_fork=false
    if modulemap_is_fixed "wrappers/ios/Sources/Wrapper/module.modulemap"; then
        verify_fork=true
    fi
    write_summary "Verifying ${candidate_sha} against upstream ${upstream_tag} (${upstream_sha}). No tag will be published from this ${event_name} run."
    finish_check_only "$upstream_tag" "$upstream_sha" "$release_tag" "$candidate_sha" "$verify_fork" true "$verify_fork"
    exit 0
fi

if [[ "$event_name" != "schedule" && "$event_name" != "workflow_dispatch" ]]; then
    echo "Unsupported event: $event_name" >&2
    exit 1
fi

if git ls-remote --tags origin "refs/tags/${release_tag}" | grep -q .; then
    write_summary "\`${release_tag}\` already exists. Daily maintenance stops before CI."
    finish_check_only "$upstream_tag" "$upstream_sha" "$release_tag" "" false false false
    exit 0
fi

if git fetch origin "refs/heads/${branch}:refs/remotes/origin/${branch}"; then
    git switch --detach "origin/${branch}"
    if ! git merge-base --is-ancestor "$upstream_sha" HEAD; then
        if ! git merge --no-edit "$upstream_sha"; then
            git merge --abort || true
            echo "Upstream ${upstream_tag} conflicts with ${branch}. The branch was not pushed." >&2
            exit 1
        fi
    fi
else
    git switch --detach "$upstream_sha"
fi

bash "$runtime/apply.sh" "$PWD"
changed="$(git diff --name-only)"
if [[ -n "$changed" && "$changed" != "wrappers/ios/Sources/Wrapper/module.modulemap" ]]; then
    echo "The header patch changed unexpected files:" >&2
    printf '%s\n' "$changed" >&2
    exit 1
fi
if [[ -n "$changed" ]]; then
    if [[ "$dry_run" == "1" ]]; then
        echo "DRY_RUN would commit the header patch on ${branch}." >&2
        exit 0
    fi
    git -c user.name="github-actions[bot]" \
        -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
        commit -m "fix: exclude private iOS headers from the Swift umbrella."
fi

if ! modulemap_is_fixed "wrappers/ios/Sources/Wrapper/module.modulemap"; then
    echo "The header exclusions are absent after syncing ${upstream_tag}." >&2
    exit 1
fi

candidate_sha="$(git rev-parse HEAD)"
remote_sha=""
if git rev-parse --verify --quiet "refs/remotes/origin/${branch}" >/dev/null; then
    remote_sha="$(git rev-parse "refs/remotes/origin/${branch}")"
fi
if [[ "$candidate_sha" != "$remote_sha" ]]; then
    if [[ "$dry_run" == "1" ]]; then
        echo "DRY_RUN would push ${candidate_sha} to ${branch}." >&2
    elif [[ -z "${GH_TOKEN:-}" ]]; then
        echo "GH_TOKEN is required to update ${branch}." >&2
        exit 1
    else
        git -c http.extraheader="AUTHORIZATION: bearer ${GH_TOKEN}" \
            push origin "HEAD:refs/heads/${branch}"
    fi
fi

proceed_release=false
if [[ "$publish" == "true" && "$dry_run" != "1" ]]; then
    proceed_release=true
fi
write_summary "Upstream ${upstream_tag} (${upstream_sha}) has no \`${release_tag}\`. CI will verify ${candidate_sha}."
set_output proceed_release "$proceed_release"
set_output verify_fork true
set_output verify_replay true
set_output compare_modulemap true
set_output upstream_tag "$upstream_tag"
set_output upstream_sha "$upstream_sha"
set_output release_tag "$release_tag"
set_output candidate_sha "$candidate_sha"
