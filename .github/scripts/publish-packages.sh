#!/usr/bin/env bash
set -euo pipefail

# Publishes the packages built by build-deb.yml (one downloaded artifact
# directory per suite/architecture leg) to GitHub releases and to the
# GPG-signed APT repository on the gh-pages branch. Shared by
# build-and-publish.yml (daily builds) and build-releases.yml (upstream
# release builds); each leg's KIND file says which it is:
#
#   daily    prerelease "daily-<version>" per suite (all architectures of a
#            suite share it); APT component "main"; old ones pruned by
#            prune-daily-releases.sh / publish-apt-repo.sh.
#   release  release "release-<upstream tag>" per upstream release (all
#            suites/architectures share it); APT component "release";
#            never pruned.
#
# Required environment variables:
#   LEGS_DIR      Directory with one subdirectory per leg (artifact contents).
#   GH_TOKEN      Token with contents: write.
#   GH_REPO       owner/name of this repository (for gh).
#   GPG_KEY_FPR   Fingerprint of the imported APT signing key.

: "${LEGS_DIR:?}" "${GH_TOKEN:?}" "${GH_REPO:?}" "${GPG_KEY_FPR:?}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
summary="${GITHUB_STEP_SUMMARY:-/dev/stdout}"

shopt -s nullglob
legs=("$LEGS_DIR"/*/)
if [[ "${#legs[@]}" -eq 0 ]]; then
  echo 'No successfully built packages to publish.' >> "$summary"
  exit 0
fi

# Release legs in ascending upstream version order, so that when several
# releases are published in one run the newest one is created last; daily
# legs keep their (alphabetical) order.
mapfile -t legs < <(
  for leg in "${legs[@]}"; do
    printf '%s\t%s\n' "$(cat "${leg}UPSTREAM_TAG" 2>/dev/null || true)" "$leg"
  done | sort -t $'\t' -k1,1V -k2,2 | cut -f2
)

# Highest upstream release that has (or is about to get) a release here,
# to decide which one GitHub shows as "Latest".
highest_release() {
  {
    gh release list --limit 1000 --json tagName --jq '.[].tagName' \
      | sed -n 's/^release-//p'
    for leg in "${legs[@]}"; do
      if [[ "$(cat "${leg}KIND")" == release ]]; then
        cat "${leg}UPSTREAM_TAG"
      fi
    done
  } | { grep -E '^[0-9]+(\.[0-9]+)*$' || true; } | sort -V | tail -n 1
}
latest_release=""

# Tags must point to a commit that exists in this repository. Daily builds
# always do; an upstream release tag's commit normally does too (upstream
# master, which this fork merges, contains it), but fall back to the
# default branch rather than fail if it does not.
#
# The GITHUB_TOKEN may also not create a tag on a commit that itself
# changes files under .github/workflows/ (HTTP 403 "Resource not
# accessible by integration"; it lacks the "workflows" permission). The
# daily builds of synced upstream merges never hit this (the sync never
# touches workflows), but a manual build of a commit that changes a
# workflow does. Then the tag goes to the nearest ancestor that changes
# no workflow; the release notes still name the exact source commit.
commit_exists() {
  gh api "repos/${GH_REPO}/commits/$1" --silent >/dev/null 2>&1
}
workflow_free_ancestor() {
  local c
  while IFS= read -r c; do
    if [[ "$(gh api "repos/${GH_REPO}/commits/$c" \
        --jq '[.files[].filename | startswith(".github/workflows/")] | any')" == false ]]; then
      printf '%s\n' "$c"
      return 0
    fi
  done < <(gh api "repos/${GH_REPO}/commits?sha=$1&per_page=20" --jq '.[].sha')
  return 1
}
create_release() {
  # $1 = source commit; remaining arguments = gh release create arguments.
  local sha="$1" fallback
  shift
  if commit_exists "$sha"; then
    if gh release create "$@" --target "$sha"; then return 0; fi
    echo "Could not create the tag on ${sha}; trying the nearest ancestor that changes no workflow." >&2
    if fallback="$(workflow_free_ancestor "$sha")" && [[ "$fallback" != "$sha" ]]; then
      if gh release create "$@" --target "$fallback"; then return 0; fi
    fi
    echo "Falling back to the default branch for the tag." >&2
  fi
  gh release create "$@"
}

for leg in "${legs[@]}"; do
  kind=$(cat "${leg}KIND")
  version=$(cat "${leg}VERSION")
  suite=$(cat "${leg}SUITE")
  arch=$(cat "${leg}ARCH")
  source_sha=$(cat "${leg}SOURCE_SHA")
  assets=("${leg}"*.deb "${leg}"SHA256SUMS-*)
  case "$kind" in
    daily)
      tag="daily-${version//\~/-}"
      title="Daily ${version} — ${suite}"
      create_args=(--prerelease --latest=false)
      ;;
    release)
      upstream_tag=$(cat "${leg}UPSTREAM_TAG")
      tag="release-${upstream_tag}"
      title="SvxLink ${upstream_tag} (upstream release packages)"
      if [[ -z "$latest_release" ]]; then latest_release="$(highest_release)"; fi
      if [[ "$upstream_tag" == "$latest_release" ]]; then
        create_args=(--latest)
      else
        create_args=(--latest=false)
      fi
      ;;
    *) echo "Unknown KIND '$kind' in $leg" >&2; exit 1 ;;
  esac
  if gh release view "$tag" >/dev/null 2>&1; then
    gh release upload "$tag" "${assets[@]}" --clobber
  else
    create_release "$source_sha" "$tag" "${assets[@]}" \
      --title "$title" --notes-file "${leg}BUILD-INFO.MD" "${create_args[@]}"
  fi
  echo "${kind} ${suite}/${arch}: $(gh release view "$tag" --json url --jq .url)" >> "$summary"
done

# APT repository. Retried from a fresh clone if the push is rejected
# because another workflow (daily vs. release builds) pushed to gh-pages in
# the meantime: everything publish-apt-repo.sh writes is regenerated from
# the pool, so re-applying all legs onto the newer state is safe.
repo_url="https://x-access-token:${GH_TOKEN}@github.com/${GH_REPO}.git"
for attempt in 1 2 3 4 5; do
  checkout="$(mktemp -d)"
  if git ls-remote --exit-code --heads "https://github.com/${GH_REPO}.git" gh-pages >/dev/null 2>&1; then
    git clone --quiet --branch gh-pages --single-branch --depth 1 "$repo_url" "$checkout"
  else
    git clone --quiet --depth 1 "$repo_url" "$checkout"
    git -C "$checkout" checkout --quiet --orphan gh-pages
    git -C "$checkout" rm -rf --quiet . >/dev/null 2>&1 || true
  fi
  git -C "$checkout" config user.name 'github-actions[bot]'
  git -C "$checkout" config user.email '41898282+github-actions[bot]@users.noreply.github.com'

  published_legs=()
  for leg in "${legs[@]}"; do
    kind=$(cat "${leg}KIND")
    suite=$(cat "${leg}SUITE")
    arch=$(cat "${leg}ARCH")
    component=main
    if [[ "$kind" == release ]]; then component=release; fi
    for deb_file in "${leg}"*.deb; do
      REPO_DIR="$checkout" DEB_FILE="$deb_file" COMPONENT="$component" \
        SUITE="$suite" ARCH="$arch" GPG_KEY_FPR="$GPG_KEY_FPR" \
        bash "$script_dir/publish-apt-repo.sh"
    done
    label="${suite}/${arch}"
    if [[ "$kind" == release ]]; then label="$(cat "${leg}UPSTREAM_TAG") ${label}"; fi
    published_legs+=("$label")
  done

  git -C "$checkout" add -A
  if git -C "$checkout" diff --cached --quiet; then
    echo 'APT repository unchanged.' >> "$summary"
    exit 0
  fi
  git -C "$checkout" commit --quiet \
    -m "Add $(cat "${legs[0]}KIND") packages for $(IFS=,; echo "${published_legs[*]}")"
  if git -C "$checkout" push --quiet origin HEAD:refs/heads/gh-pages; then
    echo "Published ${published_legs[*]} to the APT repository (gh-pages)." >> "$summary"
    exit 0
  fi
  echo "Push to gh-pages rejected (attempt ${attempt}); retrying on the current state." >&2
  rm -rf "$checkout"
  sleep $((attempt * 15))
done
echo 'Giving up: could not push to gh-pages.' >&2
exit 1
