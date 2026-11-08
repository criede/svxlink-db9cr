#!/usr/bin/env bash
set -euo pipefail

# Renders the APT repository's start page (index.html) and its
# translations (index.<lang>.html) into a gh-pages checkout, from the
# templates in .github/pages/ and the repository's current state
# (dists/, pool/). Called by publish-apt-repo.sh after every package
# publish, and by the "Refresh start page" workflow when only the page
# templates changed.
#
# Required environment variables:
#   REPO_DIR   Path to a checkout of the gh-pages branch.

: "${REPO_DIR:?}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

repo_slug="${GITHUB_REPOSITORY:-criede/svxlink-db9cr}"

# The start page (index.html, English) and its translations
# (index.<lang>.html) are rendered from templates in .github/pages/:
#   index.html.in              English master template
#   i18n/index.<lang>.html.in  one translated template per language
#   languages.tsv              languages, their native names and the
#                              AI-translation notice in that language
# Only the parts that depend on the repository state are filled in here
# (@@SUITE_ROWS@@ etc.). Whenever the English template changes, every
# translation must be updated in the same change (rule in AGENT.MD); each
# translation records the SHA-256 of the English template it was made
# from (<meta name="source-sha256">), and a mismatch is reported as a
# warning below so a stale translation never goes unnoticed. The package
# table rows are part of the templates: keep them in sync with
# build-daily-deb.sh whenever a package's build flags or bundled
# dependencies change (see AGENT.MD).
pages_dir="$script_dir/../pages"
en_template="$pages_dir/index.html.in"
test -f "$en_template"
# Hash of the LF form, so a checkout with CRLF line endings (Windows,
# core.autocrlf) gives the same value; see check-translations.sh.
en_hash="$(tr -d '\r' < "$en_template" | sha256sum | cut -d' ' -f1)"
# In bash >= 5.2 an unquoted "&" in the replacement of ${var//pat/rep}
# stands for the matched text; the rendered values contain HTML entities.
shopt -u patsub_replacement 2>/dev/null || true

# Suite labels are proper names only, so the same in every language.
declare -A suite_labels=(
  [bookworm]="Debian 12, Raspberry Pi OS Bookworm (64/32 bit)"
  [trixie]="Debian 13, Raspberry Pi OS Trixie (64/32 bit)"
)

suite_rows=""
for d in "$REPO_DIR"/dists/*/; do
  s="$(basename "$d")"
  # Per component ("main" = daily builds, "release" = upstream releases),
  # since a component can lag behind while its builds are still pending.
  component_cells=""
  for comp in main release; do
    # A suite need not have every component (e.g. no "release" packages
    # yet): find then fails, which under pipefail would abort the whole
    # script, so a missing component directory is checked first.
    comp_archs=""
    if [[ -d "$d/$comp" ]]; then
      comp_archs="$(find "$d/$comp" -mindepth 1 -maxdepth 1 -type d -name 'binary-*' \
        -exec basename {} \; | sed 's/^binary-//' | sort -u | tr '\n' ' ')"
    fi
    comp_archs="${comp_archs% }"
    if [[ -n "$comp_archs" ]]; then
      component_cells="${component_cells}<td><code>${comp_archs}</code></td>"
    else
      component_cells="${component_cells}<td>&mdash;</td>"
    fi
  done
  label="${suite_labels[$s]:-}"
  suite_rows="${suite_rows}<tr><td><code>${s}</code></td><td>${label}</td>${component_cells}</tr>
"
done

# Packages described in the templates' package table; anything else found
# in the pool gets a visible placeholder row (in every language) so a new
# package is never silently missing from the start page.
extra_package_rows=""
while IFS= read -r pkg; do
  case "$pkg" in
    ''|svxlink|qtel) ;;
    *) extra_package_rows="${extra_package_rows}<tr><td><code>${pkg}</code></td><td>(undocumented -- please update .github/pages/index.html.in and its translations)</td></tr>
" ;;
  esac
done < <(find "$REPO_DIR/pool" -mindepth 4 -maxdepth 4 -type d -exec basename {} \; 2>/dev/null | sort -u)

# Languages with a template present, in languages.tsv order.
lang_codes=()
declare -A lang_names lang_notices
while IFS=$'\t' read -r code name notice; do
  [[ -z "$code" || "$code" == \#* ]] && continue
  if [[ "$code" != en && ! -f "$pages_dir/i18n/index.${code}.html.in" ]]; then
    echo "::warning::No translated template for language '${code}' (.github/pages/i18n/index.${code}.html.in); skipped."
    continue
  fi
  lang_codes+=("$code")
  lang_names["$code"]="$name"
  lang_notices["$code"]="$notice"
done < "$pages_dir/languages.tsv"

page_name() {
  if [[ "$1" == en ]]; then echo index.html; else echo "index.$1.html"; fi
}

hreflang_links=""
for code in "${lang_codes[@]}"; do
  hreflang_links="${hreflang_links}<link rel=\"alternate\" hreflang=\"${code}\" href=\"$(page_name "$code")\">
"
done
hreflang_links="${hreflang_links}<link rel=\"alternate\" hreflang=\"x-default\" href=\"index.html\">"

lang_switcher() {
  local current="$1" code out='<nav class="langs" aria-label="Language">'
  for code in "${lang_codes[@]}"; do
    if [[ "$code" == "$current" ]]; then
      out="${out}<strong lang=\"${code}\">${lang_names[$code]}</strong> "
    else
      out="${out}<a href=\"$(page_name "$code")\" hreflang=\"${code}\" lang=\"${code}\">${lang_names[$code]}</a> "
    fi
  done
  printf '%s</nav>' "${out% }"
}

# Remove pages of languages no longer present, then render all.
rm -f "$REPO_DIR"/index.*.html
for code in "${lang_codes[@]}"; do
  if [[ "$code" == en ]]; then
    template="$en_template"
    notice=""
  else
    template="$pages_dir/i18n/index.${code}.html.in"
    source_hash="$(sed -n 's/.*<meta name="source-sha256" content="\([0-9a-f]*\)".*/\1/p' "$template" | head -n 1)"
    if [[ "$source_hash" != "$en_hash" ]]; then
      echo "::warning::Translation '${code}' is outdated: made from a different version of .github/pages/index.html.in than the current one; update it (see AGENT.MD)."
    fi
    # Inserted by the generator rather than written into each translation,
    # so it can never be missing from a translated page.
    notice="<p class=\"ai-notice\" role=\"note\">&#9888; ${lang_notices[$code]} (<a href=\"index.html\" hreflang=\"en\" lang=\"en\">English</a>)</p>"
  fi
  page="$(cat "$template")"
  if [[ "$code" != en && "$page" != *"@@AI_NOTICE@@"* ]]; then
    page="${page/<body>/<body>
@@AI_NOTICE@@}"
  fi
  page="${page//@@REPO_SLUG@@/$repo_slug}"
  page="${page//@@HREFLANG_LINKS@@/$hreflang_links}"
  page="${page//@@LANG_SWITCHER@@/$(lang_switcher "$code")}"
  page="${page//@@AI_NOTICE@@/$notice}"
  page="${page//@@SUITE_ROWS@@/$suite_rows}"
  page="${page//@@EXTRA_PACKAGE_ROWS@@/$extra_package_rows}"
  if [[ "$page" == *"@@"* ]]; then
    echo "::warning::Unreplaced @@...@@ placeholder left in the '${code}' start page."
  fi
  printf '%s\n' "$page" > "$REPO_DIR/$(page_name "$code")"
done
