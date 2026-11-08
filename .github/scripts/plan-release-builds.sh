#!/usr/bin/env bash
set -euo pipefail

# Decides which upstream release packages build-releases.yml still has to
# build: every published (non-draft, non-prerelease) upstream release with
# a numeric tag of major version MIN_MAJOR or newer, for every target in
# .github/build-targets.json, minus the combinations already in the APT
# repository's "release" component. Release packages are built once and
# kept forever, so on a normal day this finds nothing to do; it builds the
# backlog once, then each new upstream release (and, for all kept
# releases, any target added to build-targets.json later).
#
# A combination whose build failed within the last RETRY_AFTER_DAYS days
# is not retried automatically (an emulated armhf build takes hours, and
# an old release that does not build on some target will usually keep
# failing); RETRY_FAILED=true (manual dispatch) retries it anyway.
#
# Required environment variables:
#   GH_TOKEN        Token with actions: read on this repository.
#   GH_REPO         owner/name of this repository.
#   UPSTREAM_REPO   owner/name of the upstream repository.
#   TARGETS_FILE    Path to build-targets.json.
# Optional:
#   MIN_MAJOR         Oldest major version to build. Default: 26.
#   RETRY_FAILED      "true" to also retry recently failed combinations.
#   RETRY_AFTER_DAYS  Default: 7.
#   WORKFLOW_FILE     Default: build-releases.yml.
# Writes "matrix" (JSON for strategy.matrix) and "count" to $GITHUB_OUTPUT.

: "${GH_TOKEN:?}" "${GH_REPO:?}" "${UPSTREAM_REPO:?}" "${TARGETS_FILE:?}"
MIN_MAJOR="${MIN_MAJOR:-26}"
RETRY_FAILED="${RETRY_FAILED:-false}"
RETRY_AFTER_DAYS="${RETRY_AFTER_DAYS:-7}"
WORKFLOW_FILE="${WORKFLOW_FILE:-build-releases.yml}"
output="${GITHUB_OUTPUT:-/dev/stdout}"
summary="${GITHUB_STEP_SUMMARY:-/dev/stdout}"

# jq failures inside the process substitutions below would not stop the
# script and would silently look like "nothing to build"; check up front.
command -v jq >/dev/null
target_count="$(jq 'length' "$TARGETS_FILE")"
[[ "$target_count" =~ ^[1-9][0-9]*$ ]]

mapfile -t tags < <(
  gh api --paginate "repos/${UPSTREAM_REPO}/releases" \
    --jq '.[] | select(.draft | not) | select(.prerelease | not) | .tag_name' \
  | { grep -E '^[0-9]+(\.[0-9]+)*$' || true; } \
  | awk -F. -v min="$MIN_MAJOR" '$1 + 0 >= min' | sort -uV
)
echo "Upstream releases considered (major >= ${MIN_MAJOR}): ${tags[*]:-none}" >> "$summary"

# Package files already published per suite (component "release").
declare -A published
for suite in $(jq -r '.[].suite' "$TARGETS_FILE" | sort -u); do
  if names=$(gh api "repos/${GH_REPO}/contents/pool/${suite}/release/s/svxlink?ref=gh-pages" \
      --jq '.[].name' 2>/dev/null); then
    while IFS= read -r name; do
      [[ -n "$name" ]] && published["$name"]=1
    done <<< "$names"
  fi
done

# Combinations that failed recently, from this workflow's own run history.
# Job names are "<tag> <suite>/<arch> / build" (see build-releases.yml).
declare -A failed
if [[ "$RETRY_FAILED" != true ]]; then
  since="$(date -u -d "${RETRY_AFTER_DAYS} days ago" +%Y-%m-%d)"
  mapfile -t run_ids < <(gh run list --repo "$GH_REPO" --workflow "$WORKFLOW_FILE" \
    --created ">=${since}" --limit 100 --json databaseId --jq '.[].databaseId' 2>/dev/null || true)
  for run_id in "${run_ids[@]}"; do
    while IFS= read -r name; do
      if [[ "$name" =~ ^([0-9.]+)\ ([a-z0-9]+)/([a-z0-9]+)\ /\ build$ ]]; then
        failed["${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]}"]=1
      fi
    done < <(gh run view "$run_id" --repo "$GH_REPO" --json jobs \
      --jq '.jobs[] | select(.conclusion == "failure" or .conclusion == "timed_out") | .name' \
      2>/dev/null || true)
  done
fi

entries=()
skipped=()
for tag in "${tags[@]}"; do
  while IFS=$'\t' read -r suite arch target_json; do
    deb="svxlink_${tag}-1~${suite}_${arch}.deb"
    [[ -n "${published[$deb]:-}" ]] && continue
    if [[ -n "${failed["$tag $suite $arch"]:-}" ]]; then
      skipped+=("$tag $suite/$arch")
      continue
    fi
    entries+=("$(jq -c --arg tag "$tag" '. + {tag: $tag}' <<< "$target_json")")
  done < <(jq -r '.[] | [.suite, .arch, (. | tojson)] | @tsv' "$TARGETS_FILE")
done

if [[ "${#skipped[@]}" -gt 0 ]]; then
  echo "Not retried (failed within the last ${RETRY_AFTER_DAYS} days; dispatch with retry_failed to force): ${skipped[*]}" >> "$summary"
fi

if [[ "${#entries[@]}" -eq 0 ]]; then
  echo 'Nothing to build: all upstream release packages are published.' >> "$summary"
  echo 'matrix={"include":[]}' >> "$output"
  echo 'count=0' >> "$output"
  exit 0
fi

matrix="$(printf '%s\n' "${entries[@]}" | jq -cs '{include: .}')"
echo "To build (${#entries[@]}): $(printf '%s\n' "${entries[@]}" | jq -r '"\(.tag) \(.suite)/\(.arch)"' | paste -sd, -)" >> "$summary"
echo "matrix=${matrix}" >> "$output"
echo "count=${#entries[@]}" >> "$output"
