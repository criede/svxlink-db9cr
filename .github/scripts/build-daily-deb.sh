#!/usr/bin/env bash
set -euo pipefail

# Runs in a disposable native Debian/Ubuntu container, without a GitHub token.
# The target architecture and distribution codename are taken from the
# container itself, so the same script builds packages for other Raspberry
# Pi OS/Debian/Ubuntu versions and architectures by simply running it in a
# different --platform/base image.
export DEBIAN_FRONTEND=noninteractive
arch=$(dpkg --print-architecture)
# Parsed as plain text rather than sourced: /etc/os-release is only meant
# to hold KEY=VALUE pairs, but sourcing it would execute its content as
# shell code if it ever contained anything else.
codename=$(sed -n 's/^VERSION_CODENAME=//p' /etc/os-release | tr -d '"')
[[ "$codename" =~ ^[a-z0-9]+$ ]]
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates git cmake build-essential pkg-config dpkg-dev file \
  doxygen groff libsigc++-2.0-dev libgsm1-dev libpopt-dev tcl8.6-dev \
  libgcrypt20-dev libspeex-dev libasound2-dev libopus-dev libusb-1.0-0-dev \
  libjsoncpp-dev libcurl4-openssl-dev libgpiod-dev libogg-dev ladspa-sdk libssl-dev

# dpkg-architecture needs dpkg-dev, installed just above.
multiarch=$(dpkg-architecture -qDEB_HOST_MULTIARCH)

# Build the RTL-SDR Blog fork of librtlsdr/rtl_tcp from source instead of
# using the distro's librtlsdr-dev: Debian's librtlsdr is typically too old
# to support current RTL-SDR Blog V3/V4 dongles. Installed to /usr/local
# only for this build container to discover via the default CMake/pkg-config
# search paths; the resulting shared library and tools are bundled into the
# svxlink package itself below (see bundle-extra-libs.cmake), not left as a
# separate system-wide install.
git clone --depth 1 https://github.com/rtlsdrblog/rtl-sdr-blog.git /tmp/rtl-sdr-blog
cmake -S /tmp/rtl-sdr-blog -B /tmp/rtl-sdr-blog/build \
  -DCMAKE_BUILD_TYPE=Release -DDETACH_KERNEL_DRIVER=ON
cmake --build /tmp/rtl-sdr-blog/build --parallel "$(nproc)"
cmake --install /tmp/rtl-sdr-blog/build --prefix /usr/local

# Build PJSIP/pjproject from source for the contributed SipLogic logic core:
# it is not packaged in Debian. Its libraries build static by default, so
# SipLogic.so links pjproject in directly; nothing extra needs to be bundled
# or added to Depends for it. -fPIC is required since those static libs end
# up linked into SipLogic.so, a shared object; pjproject does not enable it
# by default.
git clone --depth 1 --branch master https://github.com/pjsip/pjproject.git /tmp/pjproject
(
  cd /tmp/pjproject
  export CFLAGS="-fPIC ${CFLAGS:-}"
  export CXXFLAGS="-fPIC ${CXXFLAGS:-}"
  ./configure --prefix=/usr/local --disable-video --disable-libwebrtc
  make dep
  make -j"$(nproc)"
  make install
)
ldconfig

git config --global --add safe.directory /source
source_sha=$(git -C /source rev-parse HEAD)
base_version=$(sed -n 's/^PROJECT=//p' /source/src/versions | tr -d '\r')
[[ "$base_version" =~ ^[0-9]+(\.[0-9]+)*$ ]]
version="${base_version}+daily$(date -u +%Y%m%d).${GITHUB_RUN_NUMBER}.${GITHUB_RUN_ATTEMPT}.g${source_sha:0:12}-1~${codename}"
dpkg --validate-version "$version"

# Copies the RTL-SDR Blog librtlsdr/rtl_tcp build (installed to /usr/local
# above) into the package's own staging tree during CPack's install phase,
# so it ships as part of the svxlink package itself rather than depending on
# (or colliding with) any system-wide librtlsdr/rtl-sdr installation.
# /build is created here explicitly: it is otherwise only created as a side
# effect of the "cmake -S -B /build" configure call further down, which
# races with writing into it.
mkdir -p /build
cat > /build/bundle-extra-libs.cmake <<CMAKE_EOF
file(GLOB rtlsdr_libs "/usr/local/lib/librtlsdr.so*" "/usr/local/lib/*/librtlsdr.so*")
file(MAKE_DIRECTORY "\$ENV{DESTDIR}/usr/lib/${multiarch}")
foreach(f \${rtlsdr_libs})
  file(COPY "\${f}" DESTINATION "\$ENV{DESTDIR}/usr/lib/${multiarch}" FOLLOW_SYMLINK_CHAIN)
endforeach()
file(MAKE_DIRECTORY "\$ENV{DESTDIR}/usr/bin")
foreach(prog rtl_tcp rtl_sdr rtl_eeprom rtl_test)
  if(EXISTS "/usr/local/bin/\${prog}")
    file(COPY "/usr/local/bin/\${prog}" DESTINATION "\$ENV{DESTDIR}/usr/bin"
      FILE_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE
                        GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)
  endif()
endforeach()
CMAKE_EOF

cmake -S /source/src -B /build \
  -DCMAKE_BUILD_TYPE=Release -DUSE_QT=OFF -DWITH_SYSTEMD=ON -DDO_INSTALL_CHOWN=OFF \
  -DWITH_CONTRIB_SIP_LOGIC=ON \
  -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_SYSCONFDIR=/etc \
  -DCMAKE_INSTALL_LOCALSTATEDIR=/var \
  -DSYSTEMD_CONFIGURATIONS_FILES_DIR=/usr/lib/systemd/system \
  -DCPACK_GENERATOR=DEB \
  -DCPACK_DEBIAN_PACKAGE_VERSION="$version" \
  -DCPACK_DEBIAN_PACKAGE_ARCHITECTURE="$arch" \
  -DCPACK_DEBIAN_FILE_NAME=DEB-DEFAULT \
  -DCPACK_DEBIAN_PACKAGE_SHLIBDEPS=ON \
  -DCPACK_INSTALL_SCRIPT=/build/bundle-extra-libs.cmake \
  '-DCPACK_DEBIAN_PACKAGE_DEPENDS=adduser, libc-bin, alsa-utils, vorbis-tools, tcl8.6' \
  '-DCPACK_DEBIAN_PACKAGE_CONFLICTS=svxlink-server, svxreflector, remotetrx, librtlsdr0, rtl-sdr' \
  -DCPACK_DEBIAN_PACKAGE_CONTROL_STRICT_PERMISSION=ON \
  2>&1 | tee /build/configure.log

# Speex, Opus and LADSPA are optional upstream dependencies that silently
# disable the corresponding feature if not found; libspeex-dev, libopus-dev
# and ladspa-sdk above are meant to make them mandatory for this package,
# so fail loudly instead of shipping a silently degraded build if any of
# them was not actually detected.
! grep -q "without it but support for the Speex audio codec" /build/configure.log
! grep -q "without it but support for the Opus audio codec" /build/configure.log
! grep -q "without it but support for loading LADSPA plugins" /build/configure.log
! grep -q "Accessing GPIO pins using GPIOD will be unavailable" /build/configure.log

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
# Captured first rather than piped straight into grep -q: grep -q exits as
# soon as it finds a match without reading the rest of stdin, which under
# pipefail can make dpkg-deb's SIGPIPE-killed tar subprocess register as a
# pipeline failure even though the match was found.
package_contents="$(dpkg-deb -c "${packages[0]}")"
grep -q '/librtlsdr\.so' <<< "$package_contents"
grep -q '/SipLogic\.so' <<< "$package_contents"
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
- RTL-SDR support uses a from-source build of the RTL-SDR Blog librtlsdr/
  rtl_tcp fork (bundled in this package), for current V3/V4 dongle support;
  it conflicts with the distro's librtlsdr0/rtl-sdr packages.
- Contributed SipLogic logic core enabled, linked against a from-source
  PJSIP/pjproject build (statically linked into SipLogic.so).
- Built natively in Debian ${codename}; package installation is smoke-tested in a clean container.
- Radio hardware and audio operation have not been tested by CI.

Install with \`sudo apt install ./svxlink_*.deb\` after downloading the package,
or via the APT repository: https://criede.github.io/svxlink-db9cr/
Configure the station and install the appropriate sound pack before starting SvxLink.
EOF
cd /output
sha256sum ./*.deb > SHA256SUMS
