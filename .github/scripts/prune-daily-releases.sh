#!/usr/bin/env bash
set -euo pipefail

# Deletes daily prereleases (and their tags) that fall outside the
# grandfather-father-son retention window from gfs-retention.sh, applied
# separately per suite so every currently maintained suite always keeps
# its own recent history.
#
# Tags look like "daily-<version>", where <version> ends in "-1-deb<N>"
# (the "~deb<N>" version suffix with "~" replaced by "-"; N = Debian major
# version) and contains a "+daily<YYYYMMDD>" marker. Builds from before the
# switch to numeric suffixes end in "-1-<codename>" instead ("-1-trixie");
# those codenames are mapped to their "deb<N>" series below, so old and new
# tags of one suite share a single retention series rather than being
# pruned as two separate ones. Tags that do not match this shape are left
# alone.
#
# Requires: gh (authenticated via GH_TOKEN), repo in GH_REPO/GH_TOKEN env.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
today="$(date -u +%Y%m%d)"

mapfile -t tags < <(gh release list --limit 1000 --json tagName --jq '.[].tagName' \
  | grep '^daily-' || true)

if [[ "${#tags[@]}" -eq 0 ]]; then
  echo "No daily releases found."
  exit 0
fi

declare -A suite_pairs
for tag in "${tags[@]}"; do
  if [[ "$tag" =~ \+daily([0-9]{8}) ]]; then
    date="${BASH_REMATCH[1]}"
    suite="${tag##*-}"
    case "$suite" in
      bookworm) suite=deb12 ;;
      trixie)   suite=deb13 ;;
    esac
    suite_pairs["$suite"]+="${date} ${tag}"$'\n'
  else
    echo "Skipping tag with unexpected shape: $tag"
  fi
done

declare -A keep
for suite in "${!suite_pairs[@]}"; do
  while IFS= read -r tag; do
    [[ -n "$tag" ]] && keep["$tag"]=1
  done < <(printf '%s' "${suite_pairs[$suite]}" | bash "$script_dir/gfs-retention.sh" "$today")
done

deleted=0
for tag in "${tags[@]}"; do
  if [[ "$tag" =~ \+daily([0-9]{8}) ]] && [[ -z "${keep[$tag]:-}" ]]; then
    echo "Deleting release outside retention window: $tag"
    gh release delete "$tag" --yes --cleanup-tag
    deleted=$((deleted + 1))
  fi
done

echo "Deleted ${deleted} daily release(s); kept $(( ${#tags[@]} - deleted )) of ${#tags[@]}."
