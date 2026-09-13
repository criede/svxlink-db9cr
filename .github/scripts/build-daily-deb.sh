#!/usr/bin/env bash
set -euo pipefail

# Runs in a disposable native Debian/Ubuntu container, without a GitHub token.
# The target architecture and distribution codename are taken from the
# container itself, so the same script builds packages for other Raspberry
# Pi OS/Debian/Ubuntu versions and architectures by simply running it in a
# different --platform/base image.
export DEBIAN_FRONTEND=noninteractive
arch=$(dpkg --print-architecture)
codename=$(. /etc/os-release && echo "$VERSION_CODENAME")
test -n "$codename"
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates git cmake build-essential pkg-config dpkg-dev file \
  doxygen groff libsigc++-2.0-dev libgsm1-dev libpopt-dev tcl8.6-dev \
  libgcrypt20-dev libspeex-dev libasound2-dev libopus-dev librtlsdr-dev \
  libjsoncpp-dev libcurl4-openssl-dev libgpiod-dev libogg-dev ladspa-sdk libssl-dev

git config --global --add safe.directory /source
source_sha=$(git -C /source rev-parse HEAD)
base_version=$(sed -n 's/^PROJECT=//p' /source/src/versions | tr -d '\r')
[[ "$base_version" =~ ^[0-9]+(\.[0-9]+)*$ ]]
version="${base_version}+daily$(date -u +%Y%m%d).${GITHUB_RUN_NUMBER}.${GITHUB_RUN_ATTEMPT}.g${source_sha:0:12}-1~${codename}"
dpkg --validate-version "$version"

cmake -S /source/src -B /build \
  -DCMAKE_BUILD_TYPE=Release -DUSE_QT=OFF -DWITH_SYSTEMD=ON -DDO_INSTALL_CHOWN=OFF \
  -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_SYSCONFDIR=/etc \
  -DCMAKE_INSTALL_LOCALSTATEDIR=/var \
  -DSYSTEMD_CONFIGURATIONS_FILES_DIR=/usr/lib/systemd/system \
  -DCPACK_GENERATOR=DEB \
  -DCPACK_DEBIAN_PACKAGE_VERSION="$version" \
  -DCPACK_DEBIAN_PACKAGE_ARCHITECTURE="$arch" \
  -DCPACK_DEBIAN_FILE_NAME=DEB-DEFAULT \
  -DCPACK_DEBIAN_PACKAGE_SHLIBDEPS=ON \
  '-DCPACK_DEBIAN_PACKAGE_DEPENDS=adduser, libc-bin, alsa-utils, vorbis-tools, tcl8.6' \
  '-DCPACK_DEBIAN_PACKAGE_CONFLICTS=svxlink-server, svxreflector, remotetrx' \
  -DCPACK_DEBIAN_PACKAGE_CONTROL_STRICT_PERMISSION=ON
cmake --build /build --parallel "$(nproc)"

# CPack's upstream maintainer script has no shebang; make it executable and
# refresh the linker cache for the bundled shared libraries after installation.
{
  printf '#!/bin/sh\nset -e\n'
  cat /build/postinst
  printf '\nldconfig\n'
} > /build/postinst.daily
mv /build/postinst.daily /build/postinst
chmod 0755 /build/postinst
cpack --config /build/CPackConfig.cmake -G DEB -B /output

shopt -s nullglob
packages=(/output/*.deb)
test "${#packages[@]}" -eq 1
test "$(dpkg-deb -f "${packages[0]}" Architecture)" = "$arch"
test "$(dpkg-deb -f "${packages[0]}" Version)" = "$version"
test -n "$(dpkg-deb -f "${packages[0]}" Depends)"
dpkg-deb --info "${packages[0]}"
printf '%s\n' "$version" > /output/VERSION
printf '%s\n' "$codename" > /output/SUITE
printf '%s\n' "$arch" > /output/ARCH
cat > /output/BUILD-INFO.MD <<EOF
Daily development build of svxlink-db9cr, not a stable release.

- Target: Debian/Raspberry Pi OS ${codename} (${arch}).
- Package version: ${version}
- Source commit: ${source_sha}
- Build: ${GITHUB_RUN_NUMBER}, attempt ${GITHUB_RUN_ATTEMPT}
- Server build without Qtel; upstream sound packs are not bundled.
- Built natively in Debian ${codename}; package installation is smoke-tested in a clean container.
- Radio hardware and audio operation have not been tested by CI.

Install with \`sudo apt install ./svxlink_*.deb\` after downloading the package,
or via the APT repository: https://criede.github.io/svxlink-db9cr/
Configure the station and install the appropriate sound pack before starting SvxLink.
EOF
cd /output
sha256sum ./*.deb > SHA256SUMS
