#!/usr/bin/env bash
set -euo pipefail

# Grandfather-father-son retention: decides which of a set of dated,
# per-day entries to keep. Shared by the daily GitHub prerelease cleanup
# and the APT repository pool pruning, so both age out old builds the
# same way instead of each having its own ad hoc rule.
#
# Policy, relative to "today":
#   age <   7 days: keep every entry (one bucket per day)
#   age <  30 days: keep the newest entry per ISO week
#   age < 365 days: keep the newest entry per calendar month
#   age >= 365 days: drop
#
# Usage:
#   bash gfs-retention.sh <today-YYYYMMDD> < input > output
#     stdin:  "<YYYYMMDD> <identifier>" per line (identifier has no spaces)
#     stdout: the identifiers to KEEP, one per line (unordered)
#
# Entries are typically pre-grouped by the caller (e.g. per suite) before
# being passed in, since retention is meant to apply per independent
# series, not across unrelated ones.

today="${1:?today (YYYYMMDD) required}"
today_epoch=$(date -u -d "$today" +%s)

declare -A bucket_best_date
declare -A bucket_best_id

while IFS=' ' read -r entry_date id; do
  [[ -z "$entry_date" ]] && continue
  entry_epoch=$(date -u -d "$entry_date" +%s)
  age_days=$(( (today_epoch - entry_epoch) / 86400 ))
  if (( age_days < 7 )); then
    bucket="d:$entry_date"
  elif (( age_days < 30 )); then
    bucket="w:$(date -u -d "$entry_date" +%G-%V)"
  elif (( age_days < 365 )); then
    bucket="m:$(date -u -d "$entry_date" +%Y-%m)"
  else
    continue
  fi
  # Keep only the newest entry per bucket.
  if [[ -z "${bucket_best_date[$bucket]:-}" ]] || [[ "$entry_date" > "${bucket_best_date[$bucket]}" ]]; then
    bucket_best_date["$bucket"]="$entry_date"
    bucket_best_id["$bucket"]="$id"
  fi
done

for bucket in "${!bucket_best_id[@]}"; do
  printf '%s\n' "${bucket_best_id[$bucket]}"
done
