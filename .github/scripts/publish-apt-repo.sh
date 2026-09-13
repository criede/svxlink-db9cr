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
#   RETENTION     Number of package versions to keep per suite/component/
#                 architecture/package. Older ones are pruned so the branch
#                 does not grow without bound. Default: 14.

: "${REPO_DIR:?}" "${DEB_FILE:?}" "${SUITE:?}" "${ARCH:?}" "${GPG_KEY_FPR:?}"
COMPONENT="${COMPONENT:-main}"
RETENTION="${RETENTION:-14}"

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

# Prune older versions of this package for this suite/arch, keeping the
# $RETENTION most recently published ones.
shopt -s nullglob
existing=("$pool_dir"/"${pkg_name}"_*_"${ARCH}".deb)
if [[ "${#existing[@]}" -gt "$RETENTION" ]]; then
  # Oldest first; drop everything but the newest $RETENTION.
  mapfile -t sorted_oldest_first < <(ls -t "${existing[@]}" | tac)
  drop_count=$(( ${#sorted_oldest_first[@]} - RETENTION ))
  for ((i = 0; i < drop_count; i++)); do
    echo "Pruning old package: ${sorted_oldest_first[$i]}"
    rm -f -- "${sorted_oldest_first[$i]}"
  done
fi

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

repo_slug="${GITHUB_REPOSITORY:-criede/svxlink-db9cr}"
docs_url="https://github.com/${repo_slug}/blob/master/.github/UPSTREAM-SYNC.MD"
cat > "$REPO_DIR/index.html" <<EOF
<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>SvxLink DB9CR APT repository</title></head>
<body>
<h1>SvxLink DB9CR APT repository</h1>
<p>Daily development packages of
<a href="https://github.com/${repo_slug}">svxlink-db9cr</a>.</p>
<p><strong>Documentation:</strong>
<a href="${docs_url}">UPSTREAM-SYNC.MD</a>
&mdash; setup, signing key rotation and
<a href="${docs_url}#einbindung-auf-raspberry-pi-os-und-debian">install instructions for Raspberry Pi OS and Debian</a>.</p>
<p>Public signing key: <a href="pubkey.gpg">pubkey.gpg</a></p>
<p>Available suites/architectures:</p>
<ul>
$(cd "$REPO_DIR/dists" && for d in */; do s="${d%/}"; echo "<li>$s: $(cd "$s" 2>/dev/null && find . -maxdepth 2 -type d -name 'binary-*' -exec basename {} \; | sed 's/^binary-//' | sort -u | tr '\n' ' ')</li>"; done)
</ul>
</body>
</html>
EOF
