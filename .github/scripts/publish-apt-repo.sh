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
# the same grandfather-father-son policy in gfs-retention.sh as the daily
# GitHub prereleases (prune-daily-releases.sh), so the pool never retains
# more than the releases do and the branch does not grow without bound.

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


# Start page and its translations (see render-start-page.sh).
REPO_DIR="$REPO_DIR" bash "$script_dir/render-start-page.sh"
