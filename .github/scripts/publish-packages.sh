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

# Validate every leg before anything is published. The artifacts are
# written by the build container, which runs third-party and upstream build
# code as root, while this job holds the APT signing key and a write token:
# nothing in an artifact is trusted beyond what is checked here. The kind,
# suite, architecture and (for releases) upstream tag are taken from what
# the workflow itself decided -- EXPECTED_KIND and the artifact name, which
# comes from the workflow's matrix -- and every metadata file and package
# must agree with them. Only regular files of the expected names are
# accepted, and only the svxlink and qtel packages, so a compromised build
# cannot get other packages (e.g. a fake openssh-server) signed into the
# repository or a daily build into the "release" component.
#   EXPECTED_KIND        daily | release (required)
#   EXPECTED_SOURCE_SHA  for daily: the commit that was meant to be built
: "${EXPECTED_KIND:?}"
[[ "$EXPECTED_KIND" == daily || "$EXPECTED_KIND" == release ]]

# Expected version suffix "~deb<N>" per suite and the release revision,
# both from this (trusted) checkout -- .github/build-targets.json and
# release-debian-revision -- never from the artifact.
targets_file="${script_dir}/../build-targets.json"
release_revision="$(tr -d '[:space:]' < "${script_dir}/release-debian-revision")"
[[ "$release_revision" =~ ^[1-9][0-9]*$ ]]
declare -A suite_major
while IFS=$'\t' read -r s m; do
  [[ "$s" =~ ^[a-z0-9]+$ && "$m" =~ ^[1-9][0-9]*$ ]]
  suite_major["$s"]="$m"
done < <(jq -r '.[] | [.suite, (.debian_major | tostring)] | @tsv' "$targets_file" | sort -u)

fail_leg() {
  echo "::error::Refusing to publish $(basename "$1"): $2"
  exit 1
}

validate_leg() {
  local leg="$1" name suite arch tag="" version f base pkg want_version
  name="$(basename "$leg")"
  if [[ "$EXPECTED_KIND" == daily ]]; then
    [[ "$name" =~ ^daily-deb-([a-z0-9]+)-([a-z0-9]+)$ ]] || fail_leg "$leg" "unexpected artifact name"
    suite="${BASH_REMATCH[1]}"; arch="${BASH_REMATCH[2]}"
  else
    [[ "$name" =~ ^release-deb-([0-9]+(\.[0-9]+)*)-([a-z0-9]+)-([a-z0-9]+)$ ]] || fail_leg "$leg" "unexpected artifact name"
    tag="${BASH_REMATCH[1]}"; suite="${BASH_REMATCH[3]}"; arch="${BASH_REMATCH[4]}"
  fi

  # Only regular files with known names; no symlinks, directories or extras.
  for f in "$leg"* "$leg".[!.]*; do
    [[ -e "$f" || -L "$f" ]] || continue
    base="$(basename "$f")"
    [[ -f "$f" && ! -L "$f" ]] || fail_leg "$leg" "not a regular file: $base"
    case "$base" in
      VERSION|SUITE|ARCH|KIND|SOURCE_SHA|UPSTREAM_TAG|BUILD-INFO.MD) ;;
      "SHA256SUMS-${suite}-${arch}") ;;
      svxlink_*.deb|qtel_*.deb) ;;
      *) fail_leg "$leg" "unexpected file: $base" ;;
    esac
  done

  [[ "$(cat "${leg}KIND")" == "$EXPECTED_KIND" ]] || fail_leg "$leg" "KIND mismatch"
  [[ "$(cat "${leg}SUITE")" == "$suite" ]] || fail_leg "$leg" "SUITE mismatch"
  [[ "$(cat "${leg}ARCH")" == "$arch" ]] || fail_leg "$leg" "ARCH mismatch"
  [[ "$(cat "${leg}UPSTREAM_TAG")" == "$tag" ]] || fail_leg "$leg" "UPSTREAM_TAG mismatch"
  [[ "$(cat "${leg}SOURCE_SHA")" =~ ^[0-9a-f]{40}$ ]] || fail_leg "$leg" "malformed SOURCE_SHA"
  if [[ "$EXPECTED_KIND" == daily && -n "${EXPECTED_SOURCE_SHA:-}" ]]; then
    [[ "$(cat "${leg}SOURCE_SHA")" == "$EXPECTED_SOURCE_SHA" ]] || fail_leg "$leg" "SOURCE_SHA is not the commit that was to be built"
  fi

  version="$(cat "${leg}VERSION")"
  local major="${suite_major[$suite]:-}"
  [[ -n "$major" ]] || fail_leg "$leg" "suite ${suite} has no debian_major in build-targets.json"
  if [[ "$EXPECTED_KIND" == daily ]]; then
    [[ "$version" =~ ^[0-9]+(\.[0-9]+)*\+daily[0-9]{8}\.[0-9]+\.[0-9]+\.g[0-9a-f]{12}-1~deb${major}$ ]] \
      || fail_leg "$leg" "unexpected daily version: $version"
  else
    want_version="${tag}-${release_revision}~deb${major}"
    [[ "$version" == "$want_version" ]] || fail_leg "$leg" "unexpected release version: $version"
  fi

  # Exactly one svxlink and one qtel package, whose control fields match.
  for pkg in svxlink qtel; do
    local debs=("$leg${pkg}"_*.deb)
    [[ "${#debs[@]}" -eq 1 ]] || fail_leg "$leg" "expected exactly one ${pkg} package"
    [[ "$(dpkg-deb -f "${debs[0]}" Package)" == "$pkg" ]] || fail_leg "$leg" "Package field of ${debs[0]##*/}"
    [[ "$(dpkg-deb -f "${debs[0]}" Version)" == "$version" ]] || fail_leg "$leg" "Version field of ${debs[0]##*/}"
    [[ "$(dpkg-deb -f "${debs[0]}" Architecture)" == "$arch" ]] || fail_leg "$leg" "Architecture field of ${debs[0]##*/}"
  done

  # The checksum file must cover exactly these packages, and match them.
  (cd "$leg" && sha256sum --quiet --strict -c "SHA256SUMS-${suite}-${arch}") >/dev/null \
    || fail_leg "$leg" "SHA256SUMS does not match the packages"
  [[ "$(wc -l < "${leg}SHA256SUMS-${suite}-${arch}")" -eq 2 ]] || fail_leg "$leg" "SHA256SUMS lists unexpected files"
}

for leg in "${legs[@]}"; do
  validate_leg "$leg"
done

# Release notes are written here from the validated values, not taken from
# the build container's BUILD-INFO.MD (which a compromised build could fill
# with e.g. altered install instructions).
write_notes() {
  local kind="$1" version="$2" suite="$3" source_sha="$4" tag="$5" out="$6"
  local repo_url="https://github.com/${GH_REPO}"
  local pages_url="https://${GH_REPO%%/*}.github.io/${GH_REPO#*/}/"
  {
    if [[ "$kind" == release ]]; then
      printf 'Packages of the unmodified upstream SvxLink release %s (sm0svx/svxlink tag `%s`),\n' "$tag" "$tag"
      printf 'built with the svxlink-db9cr build settings.\n\n'
    else
      printf 'Daily development build of svxlink-db9cr, not a stable release.\n\n'
    fi
    printf -- '- Target: Debian/Raspberry Pi OS %s\n' "$suite"
    printf -- '- Package version: %s\n' "$version"
    printf -- '- Source commit: %s\n\n' "$source_sha"
    printf 'Packages: `svxlink` (server components, systemd service) and the optional\n'
    printf '`qtel` (graphical EchoLink client). What is built into them, and how to\n'
    printf 'install them via the APT repository (recommended): %s\n' "$pages_url"
    printf 'Details: %s\n' "$repo_url"
  } > "$out"
}
notes_dir="$(mktemp -d)"

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

# Where the release's tag points. Preferably the exact source commit, but
# the GITHUB_TOKEN may only create a tag on a commit whose
# .github/workflows/ files are identical to the default branch's
# (otherwise HTTP 403 "Resource not accessible by integration": creating
# that ref would count as changing workflows, which needs the "workflows"
# permission the token does not have). That holds for the daily builds of
# synced upstream merges (the sync never touches workflows), but not for
# upstream release tag commits (upstream's own, different workflows) or a
# manual build of an older commit with different workflows. Those get
# their tag on the default branch instead; the release notes always name
# the exact source commit and, for releases, the upstream tag.
workflows_fingerprint() {
  gh api "repos/${GH_REPO}/contents/.github/workflows?ref=$1" \
    --jq '[.[] | .name + ":" + .sha] | sort | join(",")' 2>/dev/null || true
}
default_branch_fingerprint=""
create_release() {
  # $1 = source commit; remaining arguments = gh release create arguments.
  local sha="$1"
  shift
  if [[ -z "$default_branch_fingerprint" ]]; then
    default_branch_fingerprint="$(workflows_fingerprint \
      "$(gh api "repos/${GH_REPO}" --jq .default_branch)")"
  fi
  if [[ -n "$default_branch_fingerprint" \
        && "$(workflows_fingerprint "$sha")" == "$default_branch_fingerprint" ]]; then
    if gh release create "$@" --target "$sha"; then return 0; fi
    echo "Could not create the tag on ${sha}; using the default branch instead." >&2
  else
    echo "Workflows of ${sha} differ from the default branch's; tagging the default branch instead." >&2
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
    notes="${notes_dir}/$(basename "$leg").md"
    write_notes "$kind" "$version" "$suite" "$source_sha" "${upstream_tag:-}" "$notes"
    create_release "$source_sha" "$tag" "${assets[@]}" \
      --title "$title" --notes-file "$notes" "${create_args[@]}"
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
