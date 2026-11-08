#!/usr/bin/env bash
set -euo pipefail

# Installation smoke test for the daily packages, run inside a clean
# container of the target suite/architecture with the built .deb files
# mounted read-only at /packages. Kept as a separate script (rather than
# inline in the workflow) because 32-bit ARM packages are tested in more
# than one base image: the Raspbian image they are built in, and plain
# Debian armhf, which they are meant to install on as well.
#
# Required environment variables:
#   EXPECTED_ARCH   Debian architecture the packages must carry, e.g. "armhf".

: "${EXPECTED_ARCH:?}"
export DEBIAN_FRONTEND=noninteractive

# Fails if any shared library of the given ELF file cannot be resolved.
# Written as an explicit if rather than "! ldd ... | grep -q ...": bash
# deliberately ignores errexit for a pipeline negated with "!", so that
# form can never fail the script.
assert_libs_resolved() {
  local out
  out="$(ldd "$1")"
  if grep -q 'not found' <<< "$out"; then
    printf '%s\n' "$out" >&2
    echo "Unresolved shared libraries in $1" >&2
    exit 1
  fi
}

apt-get update
apt-get install -y --no-install-recommends /packages/*.deb

test "$(dpkg-query -W -f='${Architecture}' svxlink)" = "$EXPECTED_ARCH"
svxlink --version
test -f /usr/lib/systemd/system/svxlink.service
siplogic_so="$(find /usr/lib -name SipLogic.so -print -quit)"
test -n "$siplogic_so"
assert_libs_resolved /usr/bin/svxlink
assert_libs_resolved "$siplogic_so"

test "$(dpkg-query -W -f='${Architecture}' qtel)" = "$EXPECTED_ARCH"
test -x /usr/bin/qtel
assert_libs_resolved /usr/bin/qtel
