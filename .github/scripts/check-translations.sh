#!/usr/bin/env bash
set -euo pipefail

# Lists the state of every start-page translation against the English
# master template (.github/pages/index.html.in), for use before
# committing a change to it (see the translation rule in AGENT.MD):
#
#   bash .github/scripts/check-translations.sh          # report
#   bash .github/scripts/check-translations.sh --strict # exit 1 if any
#                                                        # is missing/outdated
#
# Prints the current hash to put into each updated translation's
#   <meta name="source-sha256" content="...">
# The hash is taken over the LF form of the file, so CRLF checkouts
# (Windows, core.autocrlf) give the same value as CI.

pages_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../pages" && pwd)"
en_hash="$(tr -d '\r' < "$pages_dir/index.html.in" | sha256sum | cut -d' ' -f1)"
echo "English template hash: ${en_hash}"

bad=0
while IFS=$'\t' read -r code _; do
  [[ -z "$code" || "$code" == \#* || "$code" == en ]] && continue
  f="$pages_dir/i18n/index.${code}.html.in"
  if [[ ! -f "$f" ]]; then
    echo "MISSING   ${code}"
    bad=1
    continue
  fi
  h="$(sed -n 's/.*<meta name="source-sha256" content="\([0-9a-f]*\)".*/\1/p' "$f" | head -n 1)"
  if [[ "$h" == "$en_hash" ]]; then
    echo "current   ${code}"
  else
    echo "OUTDATED  ${code}"
    bad=1
  fi
done < "$pages_dir/languages.tsv"

if [[ "${1:-}" == --strict && "$bad" -ne 0 ]]; then
  exit 1
fi
