#!/usr/bin/env bash
set -euo pipefail

# Runs in a disposable Debian/Raspbian/Ubuntu container of the target
# architecture (native, or QEMU-emulated for 32-bit ARM), without a GitHub
# token.
# The target architecture and distribution codename are taken from the
# container itself, so the same script builds packages for other Raspberry
# Pi OS/Debian/Ubuntu versions and architectures by simply running it in a
# different --platform/base image.
#
# Two kinds of build, selected by BUILD_KIND:
#   daily    (default) Daily development build of this repository's
#            source; version <project>+daily<date>.<run>...-1~<suite>.
#   release  Build of an unmodified upstream release tag (UPSTREAM_TAG,
#            checked out at /source); version <tag>-1~<suite>.
# The source tree is expected at /source (a git checkout).
BUILD_KIND="${BUILD_KIND:-daily}"
case "$BUILD_KIND" in
  daily) ;;
  release)
    : "${UPSTREAM_TAG:?UPSTREAM_TAG is required for BUILD_KIND=release}"
    [[ "$UPSTREAM_TAG" =~ ^[0-9]+(\.[0-9]+)*$ ]]
    ;;
  *) echo "Unknown BUILD_KIND: $BUILD_KIND" >&2; exit 1 ;;
esac
export DEBIAN_FRONTEND=noninteractive
arch=$(dpkg --print-architecture)
# Parsed as plain text rather than sourced: /etc/os-release is only meant
# to hold KEY=VALUE pairs, but sourcing it would execute its content as
# shell code if it ever contained anything else.
codename=$(sed -n 's/^VERSION_CODENAME=//p' /etc/os-release | tr -d '"')
[[ "$codename" =~ ^[a-z0-9]+$ ]]
# "debian" or "raspbian": 32-bit ARM (armhf) is built in a Raspbian
# container rather than Debian's own armhf, since Raspbian targets
# ARMv6+VFP and so also runs on the Raspberry Pi 1/Zero/Zero W, which
# Debian armhf (ARMv7) does not. The result installs on Debian armhf too.
os_id=$(sed -n 's/^ID=//p' /etc/os-release | tr -d '"')
[[ "$os_id" =~ ^[a-z0-9]+$ ]]
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
if [[ "$BUILD_KIND" == release ]]; then
  # A release tag's src/versions must name that very release; anything
  # else means the wrong tree was checked out.
  if [[ "$base_version" != "$UPSTREAM_TAG" ]]; then
    echo "src/versions says PROJECT=${base_version}, expected ${UPSTREAM_TAG}." >&2
    exit 1
  fi
  # Deliberately no date/run/commit part: one upstream release maps to
  # exactly one package version per suite, built once and never rebuilt
  # (the planning step only builds combinations missing from the pool).
  # The "-1" Debian revision sorts below the "+daily" builds of the same
  # project version, which are newer code.
  version="${UPSTREAM_TAG}-1~${codename}"
fi
# Between releases upstream sets PROJECT=master instead of a number (it
# alternates: "Prepare for release X" sets it, "Set PROJECT version to
# master" resets it). Fall back to the highest numeric PROJECT value ever
# recorded in src/versions' history (needs the full-depth checkout the
# workflow already does), so daily builds keep a valid, monotonically
# increasing Debian version instead of aborting the build.
if [[ "$BUILD_KIND" == daily && ! "$base_version" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
  echo "PROJECT=${base_version} in src/versions is not numeric; using the highest numeric PROJECT from its git history." >&2
  base_version=$(git -C /source log --format= -p -- src/versions \
    | sed -n 's/^[+-]\{0,1\}PROJECT=//p' | tr -d '\r' \
    | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -uV | tail -n 1 || true)
fi
if [[ ! "$base_version" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
  echo "Could not determine a numeric project version from src/versions." >&2
  exit 1
fi
if [[ "$BUILD_KIND" == daily ]]; then
  version="${base_version}+daily$(date -u +%Y%m%d).${GITHUB_RUN_NUMBER}.${GITHUB_RUN_ATTEMPT}.g${source_sha:0:12}-1~${codename}"
fi
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
# Written as explicit ifs rather than "! grep -q ...": bash deliberately
# ignores errexit for a command negated with "!", so that form never fails.
for missing_feature_msg in \
  "without it but support for the Speex audio codec" \
  "without it but support for the Opus audio codec" \
  "without it but support for loading LADSPA plugins" \
  "Accessing GPIO pins using GPIOD will be unavailable"; do
  if grep -qF "$missing_feature_msg" /build/configure.log; then
    echo "Required optional feature not detected: $missing_feature_msg" >&2
    exit 1
  fi
done

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
printf '%s\n' "$BUILD_KIND" > /output/KIND
printf '%s\n' "$source_sha" > /output/SOURCE_SHA
# Empty for daily builds; always written so the hand-over has a fixed shape.
printf '%s\n' "${UPSTREAM_TAG:-}" > /output/UPSTREAM_TAG
if [[ "$os_id" == raspbian ]]; then
  build_env_note="- Built in a clean Raspbian ${codename} (ARMv6+VFP) container, so it runs on
  every Raspberry Pi model with 32-bit Raspberry Pi OS (including Pi 1/Zero/
  Zero W) and also installs on Debian ${codename} armhf; package installation
  is smoke-tested in clean Raspbian and Debian containers."
else
  build_env_note="- Built in a clean Debian ${codename} container; package installation is
  smoke-tested in a clean container."
fi
if [[ "$BUILD_KIND" == release ]]; then
  build_headline="Package build of the unmodified upstream SvxLink release ${UPSTREAM_TAG}
(sm0svx/svxlink tag \`${UPSTREAM_TAG}\`, same content as its source tgz/zip),
packaged with the svxlink-db9cr build settings below. None of the
svxlink-db9cr source changes are included."
  apt_component=release
else
  build_headline="Daily development build of svxlink-db9cr, not a stable release."
  apt_component=main
fi
cat > /output/BUILD-INFO.MD <<EOF
${build_headline}

- Target: Debian/Raspberry Pi OS ${codename} (${arch}).
- Package version: ${version}
- Source commit: ${source_sha}
- Build: ${GITHUB_RUN_NUMBER}, attempt ${GITHUB_RUN_ATTEMPT}
- Server build without Qtel; the graphical EchoLink client is a separate
  optional \`qtel\` package (same version, requires a desktop environment).
  Upstream sound packs are not bundled either way.
- RTL-SDR support uses a from-source build of the RTL-SDR Blog librtlsdr/
  rtl_tcp fork (bundled in this package), for current V3/V4 dongle support;
  it conflicts with the distro's librtlsdr0/rtl-sdr packages.
- Contributed SipLogic logic core enabled, linked against a from-source
  PJSIP/pjproject build (statically linked into SipLogic.so).
${build_env_note}
- Radio hardware and audio operation have not been tested by CI.

Install with \`sudo apt install ./svxlink_*.deb\` after downloading the package
(add \`./qtel_*.deb\` too for the graphical EchoLink client), or via the APT
repository (component \`${apt_component}\`): https://criede.github.io/svxlink-db9cr/
Configure the station and install the appropriate sound pack before starting SvxLink.
EOF
# Build Qtel (graphical EchoLink client) as a second, separate package, the
# way an Arch/AUR split package works: one build, then hand-pick each
# package's own files from the shared install tree instead of shipping
# everything in one package. The main svxlink package above is deliberately
# built with -DUSE_QT=OFF so it never pulls in Qt as a runtime dependency;
# CPack has no component-based packaging set up in this tree (it would
# require tagging every install() call across the whole project), so Qtel
# gets its own full build + install into a private root instead, from which
# only its own files are copied into a hand-assembled qtel package.
# qt6-tools-dev provides the Qt6LinguistToolsConfig.cmake package config
# (needed by qtel/translations/CMakeLists.txt's find_package(Qt6LinguistTools)),
# and pulls in qt6-tools-dev-tools (lupdate/lrelease binaries) itself.
apt-get install -y --no-install-recommends \
  qt6-base-dev qt6-base-dev-tools qt6-tools-dev qt6-5compat-dev

# -std=c++17 in CMAKE_CXX_FLAGS_RELEASE: upstream's src/CMakeLists.txt
# appends FindSIGC's "--std=c++11" (libsigc++-2.0) to the global
# CMAKE_CXX_FLAGS, but Qt6 needs C++17. CMake puts the per-config flags
# after CMAKE_CXX_FLAGS on the compile line, so this wins without patching
# the source -- needed for unmodified upstream release tags, which lack
# this repository's per-target -std=c++17 fixes (harmless where present).
cmake -S /source/src -B /build-qtel \
  -DCMAKE_BUILD_TYPE=Release -DUSE_QT=ON -DWITH_SYSTEMD=OFF -DDO_INSTALL_CHOWN=OFF \
  '-DCMAKE_CXX_FLAGS_RELEASE=-O3 -DNDEBUG -std=c++17' \
  -DWITH_CONTRIB_SIP_LOGIC=OFF \
  -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_SYSCONFDIR=/etc \
  -DCMAKE_INSTALL_LOCALSTATEDIR=/var
cmake --build /build-qtel --parallel "$(nproc)"
rm -rf /qtel-root
DESTDIR=/qtel-root cmake --install /build-qtel

qtel_bin=$(find /qtel-root -type f -name qtel -path '*/bin/*' -print -quit)
test -n "$qtel_bin"
mapfile -t asyncqt_libs < <(find /qtel-root -name 'libasyncqt.so*')
test "${#asyncqt_libs[@]}" -gt 0

qtel_pkgroot=/output/qtel-pkgroot
rm -rf "$qtel_pkgroot"
install -D -m 0755 "$qtel_bin" "$qtel_pkgroot/usr/bin/qtel"
for lib in "${asyncqt_libs[@]}"; do
  install -D -m 0644 "$lib" "$qtel_pkgroot/${lib#/qtel-root/}"
done
mkdir -p "$qtel_pkgroot/usr/share"
cp -a /qtel-root/usr/share/qtel "$qtel_pkgroot/usr/share/qtel"
install -D -m 0644 /qtel-root/usr/share/applications/qtel.desktop \
  "$qtel_pkgroot/usr/share/applications/qtel.desktop"
install -D -m 0644 /qtel-root/usr/share/icons/hicolor/128x128/apps/qtel.png \
  "$qtel_pkgroot/usr/share/icons/hicolor/128x128/apps/qtel.png"
install -D -m 0644 /qtel-root/usr/share/metainfo/org.svxlink.Qtel.metainfo.xml \
  "$qtel_pkgroot/usr/share/metainfo/org.svxlink.Qtel.metainfo.xml"

# Runtime dependencies for Qt/GSM/etc. are resolved with dpkg-shlibdeps
# rather than hand-listed, since exact package names (e.g. the "t64" time_t
# transition affecting trixie but not bookworm) differ between suites.
# echolib/asyncaudio/asynccore (needed by qtel, shared with the svxlink
# package built above) are private project libraries, not a Debian
# package: dpkg-shlibdeps cannot even locate them without help ("cannot
# find library", not just "missing info", which --ignore-missing-info does
# not cover) -- point it at their directory with -l instead, so it can
# find them but (since there is still no shlibs/symbols file for them)
# --ignore-missing-info then correctly skips adding a dependency for them,
# relying on "Depends: svxlink (= same version)" to cover them instead.
mkdir -p /tmp/qtel-shlibdeps/debian
cat > /tmp/qtel-shlibdeps/debian/control <<EOF
Source: qtel
Section: hamradio
Priority: optional
Maintainer: SvxLink Community <svxlink@groups.io>

Package: qtel
Architecture: any
Depends: \${shlibs:Depends}, \${misc:Depends}
Description: Graphical EchoLink client for SvxLink
EOF
(
  cd /tmp/qtel-shlibdeps
  dpkg-shlibdeps --ignore-missing-info -O \
    "-l/qtel-root/usr/lib/${multiarch}" \
    "$qtel_pkgroot/usr/bin/qtel" "${asyncqt_libs[@]}" \
    > shlibdeps.out
)
shlibs_depends=$(sed -n 's/^shlibs:Depends=//p' /tmp/qtel-shlibdeps/shlibdeps.out)
test -n "$shlibs_depends"

mkdir -p "$qtel_pkgroot/DEBIAN"
cat > "$qtel_pkgroot/DEBIAN/control" <<EOF
Package: qtel
Version: $version
Architecture: $arch
Maintainer: SvxLink Community <svxlink@groups.io>
Depends: svxlink (= $version), ${shlibs_depends}
Section: hamradio
Priority: optional
Description: Graphical EchoLink client for SvxLink
 Qtel is the graphical EchoLink client bundled with SvxLink. Built from
 the same daily source as the svxlink package and pinned to the exact
 same version, since it shares that package's echolib/async libraries.
EOF
printf '#!/bin/sh\nset -e\nldconfig\n' > "$qtel_pkgroot/DEBIAN/postinst"
chmod 0755 "$qtel_pkgroot/DEBIAN/postinst"
find "$qtel_pkgroot" -mindepth 1 -not -path "$qtel_pkgroot/DEBIAN*" -exec chmod go-w {} +

dpkg-deb --build --root-owner-group "$qtel_pkgroot" \
  "/output/qtel_${version}_${arch}.deb"
dpkg-deb -f "/output/qtel_${version}_${arch}.deb" Depends

cd /output
# Per-suite/architecture name: several legs share one GitHub release (all
# architectures of a suite share a daily prerelease; all suites and
# architectures share an upstream release's), so a plain "SHA256SUMS"
# asset would be overwritten by whichever leg is published last.
sha256sum ./*.deb > "SHA256SUMS-${codename}-${arch}"
