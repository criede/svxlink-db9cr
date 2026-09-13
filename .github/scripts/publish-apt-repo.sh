#!/usr/bin/env bash
set -euo pipefail

# Publishes one built .deb into a standard APT repository layout (checked out
# from the gh-pages branch) and (re)signs the affected suite's Release file.
#
# Layout, extensible to further Raspberry Pi OS / Debian / Ubuntu versions
# and architectures by simply calling this script again with different
# SUITE/ARCH values:
#
#   dists/<suite>/InRelease
#   dists/<suite>/Release
#   dists/<suite>/Release.gpg
#   dists/<suite>/<component>/binary-<arch>/Packages[.gz]
#   pool/<suite>/<component>/<letter>/<package-name>/<package>.deb
#   pubkey.gpg                    (ASCII-armored public signing key)
#
# Required environment variables:
#   REPO_DIR      Path to a checkout of the gh-pages branch (working tree
#                 root of the APT repository).
#   DEB_FILE      Path to the .deb file to publish.
#   SUITE         Codename of the target distribution, e.g. "trixie".
#   ARCH          Debian architecture of the package, e.g. "arm64".
#   GPG_KEY_FPR   Fingerprint (or key ID) of the imported signing key.
# Optional:
#   COMPONENT     Archive component. Default: "main".
#
# Older packages are pruned per suite/component/architecture/package using
# the grandfather-father-son policy in gfs-retention.sh (daily for a week,
# weekly for a month, monthly for a year, nothing older), so the branch
# does not grow without bound.

: "${REPO_DIR:?}" "${DEB_FILE:?}" "${SUITE:?}" "${ARCH:?}" "${GPG_KEY_FPR:?}"
COMPONENT="${COMPONENT:-main}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

test -f "$DEB_FILE"
pkg_name=$(dpkg-deb -f "$DEB_FILE" Package)
test -n "$pkg_name"

case "$pkg_name" in
  lib?*) letter="${pkg_name:0:4}" ;;
  *)     letter="${pkg_name:0:1}" ;;
esac

pool_dir="$REPO_DIR/pool/$SUITE/$COMPONENT/$letter/$pkg_name"
mkdir -p "$pool_dir"
cp "$DEB_FILE" "$pool_dir/"

# Prune older versions of this package for this suite/arch according to
# the grandfather-father-son retention policy. The build date is taken
# from the "+daily<YYYYMMDD>" marker in the version string; files without
# that marker are left untouched.
shopt -s nullglob
today="$(date -u +%Y%m%d)"
dated_pairs=""
for f in "$pool_dir"/"${pkg_name}"_*_"${ARCH}".deb; do
  base="$(basename "$f")"
  if [[ "$base" =~ \+daily([0-9]{8}) ]]; then
    dated_pairs="${dated_pairs}${BASH_REMATCH[1]} ${base}"$'\n'
  fi
done

keep_set=""
if [[ -n "$dated_pairs" ]]; then
  keep_set="$(printf '%s' "$dated_pairs" | bash "$script_dir/gfs-retention.sh" "$today")"
fi

for f in "$pool_dir"/"${pkg_name}"_*_"${ARCH}".deb; do
  base="$(basename "$f")"
  if [[ "$base" =~ \+daily([0-9]{8}) ]] && ! grep -qxF "$base" <<< "$keep_set"; then
    echo "Pruning old package (outside retention window): $base"
    rm -f -- "$f"
  fi
done

dists_dir="$REPO_DIR/dists/$SUITE"
binary_dir="$dists_dir/$COMPONENT/binary-$ARCH"
mkdir -p "$binary_dir"

(
  cd "$REPO_DIR"
  dpkg-scanpackages --arch "$ARCH" "pool/$SUITE/$COMPONENT" \
    > "dists/$SUITE/$COMPONENT/binary-$ARCH/Packages" 2>/dev/null
  gzip -9 -k -f "dists/$SUITE/$COMPONENT/binary-$ARCH/Packages"
)

# Union of all components/architectures already published for this suite, so
# adding a new architecture later does not drop the existing ones from
# Release.
components=$(cd "$dists_dir" && find . -mindepth 1 -maxdepth 1 -type d \
  -exec basename {} \; | sort -u | tr '\n' ' ')
architectures=$(cd "$dists_dir" && find . -mindepth 2 -maxdepth 2 -type d \
  -name 'binary-*' -exec basename {} \; | sed 's/^binary-//' | sort -u | tr '\n' ' ')

(
  cd "$REPO_DIR"
  apt-ftparchive \
    -o APT::FTPArchive::Release::Origin="SvxLink DB9CR" \
    -o APT::FTPArchive::Release::Label="SvxLink DB9CR" \
    -o APT::FTPArchive::Release::Suite="$SUITE" \
    -o APT::FTPArchive::Release::Codename="$SUITE" \
    -o APT::FTPArchive::Release::Components="${components% }" \
    -o APT::FTPArchive::Release::Architectures="${architectures% }" \
    -o APT::FTPArchive::Release::Description="SvxLink DB9CR daily packages ($SUITE)" \
    release "dists/$SUITE" > "dists/$SUITE/Release"
)

gpg --batch --yes --local-user "$GPG_KEY_FPR" --digest-algo SHA512 \
  --detach-sign --armor -o "$dists_dir/Release.gpg" "$dists_dir/Release"
gpg --batch --yes --local-user "$GPG_KEY_FPR" --digest-algo SHA512 \
  --clearsign -o "$dists_dir/InRelease" "$dists_dir/Release"

gpg --export --armor "$GPG_KEY_FPR" > "$REPO_DIR/pubkey.gpg"
touch "$REPO_DIR/.nojekyll"

# GitHub Pages serves static files only, with no directory listing of its
# own; generate a plain "index.html" in every subdirectory (GitHub Pages
# serves <dir>/index.html automatically for a directory URL) so the "dists"
# and "pool" trees can actually be browsed link by link from the root
# index.html, down to individual Packages/Release/.deb files. The root
# index.html itself is untouched here -- it is the hand-written page below.
generate_directory_indexes() {
  local dir rel entry name size
  find "$REPO_DIR" -mindepth 1 -type d | while IFS= read -r dir; do
    rel="/${dir#"$REPO_DIR"/}"
    {
      printf '<!DOCTYPE html>\n<html lang="en">\n<head><meta charset="utf-8">\n'
      printf '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
      printf '<title>Index of %s</title>\n' "$rel"
      printf '<style>body{font-family:ui-monospace,monospace;max-width:60rem;margin:2rem auto;padding:0 1rem;}a{display:block;padding:0.15rem 0;text-decoration:none;}a:hover{text-decoration:underline;}.size{color:#888;font-size:0.9em;}</style>\n'
      printf '</head>\n<body>\n<h1>Index of %s</h1>\n<a href="../">.. (up)</a>\n' "$rel"
      for entry in "$dir"/*/; do
        [[ -e "$entry" ]] || continue
        name="$(basename "$entry")"
        printf '<a href="%s/">%s/</a>\n' "$name" "$name"
      done
      for entry in "$dir"/*; do
        [[ -f "$entry" ]] || continue
        name="$(basename "$entry")"
        [[ "$name" == "index.html" ]] && continue
        size=$(stat -c%s "$entry" 2>/dev/null || echo '?')
        printf '<a href="%s">%s <span class="size">(%s bytes)</span></a>\n' "$name" "$name" "$size"
      done
      printf '</body>\n</html>\n'
    } > "$dir/index.html"
  done
}
generate_directory_indexes

repo_slug="${GITHUB_REPOSITORY:-criede/svxlink-db9cr}"

# Human-readable label per known suite, for the table below. Unknown
# suites (added to the matrix but not yet listed here) just show their
# codename without an extra description.
declare -A suite_labels=(
  [bookworm]="Debian 12 / Raspberry Pi OS Bookworm"
  [trixie]="Debian 13 / Raspberry Pi OS Trixie"
)

suite_rows=""
suite_list_items=""
for d in "$REPO_DIR"/dists/*/; do
  s="$(basename "$d")"
  archs="$(cd "$d" 2>/dev/null && find . -maxdepth 2 -type d -name 'binary-*' \
    -exec basename {} \; | sed 's/^binary-//' | sort -u | tr '\n' ' ')"
  archs="${archs% }"
  label="${suite_labels[$s]:-}"
  suite_rows="${suite_rows}<tr><td><code>${s}</code></td><td>${label}</td><td><code>${archs}</code></td></tr>
"
  suite_list_items="${suite_list_items}<li>${s}: ${archs}</li>
"
done

# Description per package, listing what is actually built into it. Keep in
# sync with build-daily-deb.sh whenever a package's build flags or bundled
# dependencies change (see the rule in AGENT.MD) -- this is the only place
# an end user sees what a package actually contains before installing it.
declare -A package_descriptions=(
  [svxlink]="Server components (svxlink, remotetrx, svxreflector, logic cores, Tcl event scripts). Built with: RTL-SDR direct-USB support (bundled RTL-SDR Blog librtlsdr/rtl_tcp fork for current V3/V4 dongles; conflicts with the distro librtlsdr0/rtl-sdr), the contributed SipLogic logic core (bundled PJSIP/pjproject, statically linked), GPIO via libgpiod, and Speex/Opus/LADSPA audio codec and plugin support. Installs a systemd service. Does not include Qtel or sound packs."
  [qtel]="Graphical EchoLink client (Qt6). Requires a desktop environment and the <code>svxlink</code> package of the exact same version (shares its echolib/async libraries)."
)

package_rows=""
while IFS= read -r pkg; do
  [[ -z "$pkg" ]] && continue
  desc="${package_descriptions[$pkg]:-(undocumented -- please update publish-apt-repo.sh)}"
  package_rows="${package_rows}<tr><td><code>${pkg}</code></td><td>${desc}</td></tr>
"
done < <(find "$REPO_DIR/pool" -mindepth 4 -maxdepth 4 -type d -exec basename {} \; 2>/dev/null | sort -u)

cat > "$REPO_DIR/index.html" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>SvxLink DB9CR APT repository</title>
<style>
  body { font-family: system-ui, sans-serif; max-width: 46rem; margin: 2rem auto; padding: 0 1rem; line-height: 1.5; }
  pre { background: #f0f0f0; padding: 0.75rem 1rem; overflow-x: auto; border-radius: 4px; }
  code { background: #f0f0f0; padding: 0.1rem 0.3rem; border-radius: 3px; }
  pre code { background: none; padding: 0; }
  table { border-collapse: collapse; margin: 1rem 0; }
  th, td { border: 1px solid #ccc; padding: 0.3rem 0.6rem; text-align: left; }
  .note { color: #555; font-size: 0.95em; }
</style>
</head>
<body>
<h1>SvxLink DB9CR APT repository</h1>
<p>Daily development packages of
<a href="https://github.com/${repo_slug}">svxlink-db9cr</a> for Raspberry Pi OS
and Debian. These are daily builds from the latest source, not stable
releases &mdash; see the
<a href="https://github.com/${repo_slug}">source repository</a> for details.</p>

<h2>Upstream &amp; local changes</h2>
<p>This is a daily-synced fork of
<a href="https://github.com/sm0svx/svxlink">sm0svx/svxlink</a>, the
original SvxLink project, with local packaging and feature additions
layered on top (RTL-SDR, SipLogic, the separate <code>qtel</code> package,
this APT repository, and more &mdash; see
<a href="https://github.com/${repo_slug}/blob/master/CHANGELOG.MD">CHANGELOG.MD</a>
for the full list). To see exactly what is different from upstream at any
point in time, without relying on a snapshot here going stale, compare
live on GitHub:
<a href="https://github.com/sm0svx/svxlink/compare/master...criede:svxlink-db9cr:master">upstream master&nbsp;&hellip;&nbsp;this fork's master</a>.</p>

<h2>Quickstart</h2>
<p>Run on the target system (detects the right codename/architecture automatically):</p>
<pre><code># Import the public signing key
curl -fsSL https://criede.github.io/svxlink-db9cr/pubkey.gpg | \\
  sudo gpg --dearmor -o /usr/share/keyrings/svxlink-db9cr.gpg

# Add the repository source
codename=\$(sed -n 's/^VERSION_CODENAME=//p' /etc/os-release | tr -d '"')
arch=\$(dpkg --print-architecture)
echo "deb [signed-by=/usr/share/keyrings/svxlink-db9cr.gpg arch=\${arch}] https://criede.github.io/svxlink-db9cr \${codename} main" | \\
  sudo tee /etc/apt/sources.list.d/svxlink-db9cr.list

sudo apt update
sudo apt install svxlink
# Optional graphical EchoLink client (needs a desktop environment):
# sudo apt install qtel</code></pre>
<p class="note">If <code>apt update</code> reports a 404 for this source, your
system's codename isn't built yet (see the table below) &mdash; edit the
codename in <code>/etc/apt/sources.list.d/svxlink-db9cr.list</code> to one of
the supported ones instead. Afterwards, a regular <code>sudo apt upgrade</code>
picks up new daily builds automatically.</p>

<h2>Packages</h2>
<table>
<tr><th>Package</th><th>Contains</th></tr>
${package_rows}</table>

<h2>Supported systems</h2>
<table>
<tr><th>Codename</th><th>Matches</th><th>Architectures</th></tr>
${suite_rows}</table>

<h2>Signing key</h2>
<p><a href="pubkey.gpg">pubkey.gpg</a> &mdash; imported automatically by the
quickstart commands above.</p>

<h2>Browse repository files</h2>
<p><a href="dists/">dists/</a> (per-suite indices, Release files, Packages
lists) &middot; <a href="pool/">pool/</a> (the actual <code>.deb</code>
files) &middot; <a href="https://github.com/${repo_slug}">source
repository</a> on GitHub.</p>
</body>
</html>
EOF
