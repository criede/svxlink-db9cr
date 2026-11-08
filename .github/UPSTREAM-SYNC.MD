# Daily upstream synchronization

This lives across several workflow files with separate responsibilities:

- `.github/workflows/sync-upstream.yml` merges upstream, then calls
  `build-and-publish.yml`. Specific to this fork/repository.
- `.github/workflows/build-deb.yml` is the reusable building block that
  builds and installation-tests the packages for one suite/architecture
  (see `.github/build-targets.json` for the list of targets) and hands
  them over as an Actions artifact. Used by both workflows below.
- `.github/workflows/build-releases.yml` builds packages of the upstream
  release tags (see "Upstream release packages" below).
- `.github/workflows/build-and-publish.yml` builds the daily packages and
  publishes them (GitHub prerelease, APT repository on GitHub Pages).
  Deliberately repository-agnostic: it takes the commit to build as an
  input, carries no hardcoded repository-name guard, and can be run
  standalone via `workflow_dispatch` — including, unchanged, from another
  repository such as the upstream `sm0svx/svxlink` project — as well as
  being invoked as a reusable workflow (`workflow_call`) by
  `sync-upstream.yml`.

Because of that, a run triggered from `Sync upstream` does **not** show
up under **Actions → Build and publish**'s own run history — GitHub only
lists it there for runs it dispatched directly (`workflow_dispatch`).
A `workflow_call` invocation instead executes as jobs nested inside the
*caller's* run, visible under **Actions → Sync upstream** as job names
prefixed `Build and publish / ...` (e.g. `Build and publish / trixie/arm64
daily package`). This is normal GitHub behavior for reusable workflows,
not a sign that the build is happening inside `sync-upstream.yml` itself
— that file contains no `docker run`/`cmake`/build logic at all, only the
merge and the `uses:` call.

The `Sync upstream` workflow merges all new commits from `sm0svx/svxlink`,
branch `master`, into `criede/svxlink-db9cr`, branch `master`, daily at
02:17 UTC. That corresponds to 03:17 in winter and 04:17 in summer, German
time. Other branches, tags and GitHub releases are not synchronized. Once
the merge job finishes, its `build-and-publish` job calls
`build-and-publish.yml` (`uses: ./.github/workflows/build-and-publish.yml`,
`secrets: inherit`), passing the synchronized commit as `source_sha`; this
is also where the `criede/svxlink-db9cr`-specific guard lives, so the
called workflow itself stays portable. On the daily **schedule**, that
call is additionally skipped if the merge step found nothing new
(`needs.sync.outputs.changed != 'true'`) — no point rebuilding an
unchanged commit every day. A **manual** run
(`workflow_dispatch`) always calls it regardless, e.g. to test workflow
changes without waiting for an actual upstream commit.

`.github/workflows/` is also fully excluded from the merge: before the
merge commit, this folder is reset to its own state from before the merge.
This means neither new upstream workflows are added, nor are own workflows
changed or deleted. This also applies to an otherwise possible fast-forward.
The own sync and the CodeQL deactivation are preserved.

Own changes means the changes checked in to `master` on GitHub. Unpushed
changes on a local machine are not known to the workflow. Technical errors
still abort the run. If the target branch changes in the meantime, no
force push is performed; the workflow can simply be started again
afterwards.

## Daily package for Raspberry Pi OS and Debian

After every successful sync, the `daily-deb` job runs as a matrix over all
currently maintained Debian-based target versions and architectures,
including every 32-bit variant those releases still ship as an
installable OS:

| Suite      | Debian version        | Architecture | Build image | Runner | Covers |
|------------|------------------------|--------------|-------------|--------|--------|
| `bookworm` | Debian 12 (oldstable) | `arm64`      | `debian:bookworm-slim` | `ubuntu-24.04-arm` (native) | Raspberry Pi OS Bookworm 64-bit, Debian 12 arm64 |
| `trixie`   | Debian 13 (stable)    | `arm64`      | `debian:trixie-slim`   | `ubuntu-24.04-arm` (native) | Raspberry Pi OS Trixie 64-bit, Debian 13 arm64 |
| `bookworm` | Debian 12 (oldstable) | `amd64`      | `debian:bookworm-slim` | `ubuntu-24.04` (native)     | Debian 12 on Intel/AMD (amd64) |
| `trixie`   | Debian 13 (stable)    | `amd64`      | `debian:trixie-slim`   | `ubuntu-24.04` (native)     | Debian 13 on Intel/AMD (amd64) |
| `bookworm` | Debian 12 (oldstable) | `i386`       | `debian:bookworm-slim` | `ubuntu-24.04` (native 32-bit userland) | Debian 12 on 32-bit PCs (i386) |
| `bookworm` | Debian 12 (oldstable) | `armhf`      | Raspbian bookworm (built locally) | `ubuntu-24.04` (QEMU) | Raspberry Pi OS Bookworm 32-bit (all Pi models), Debian 12 armhf |
| `trixie`   | Debian 13 (stable)    | `armhf`      | Raspbian trixie (built locally)   | `ubuntu-24.04` (QEMU) | Raspberry Pi OS Trixie 32-bit (all Pi models), Debian 13 armhf |

Debian and Raspberry Pi OS share the same package base per codename (same
library versions, same ABI); one build per suite/architecture therefore
covers both at once (where Raspberry Pi OS supports that architecture),
and a separate "Raspberry Pi OS" variant is not needed. As soon as one of
these Debian versions changes support status (e.g. a new Debian version
becomes stable), the target list in `.github/build-targets.json` (shared
by the daily and the release builds) is adjusted accordingly — older
entries removed, new ones added.

32-bit specifics:

- **armhf** is built in a Raspbian container instead of Debian's own
  `armhf`: 32-bit Raspberry Pi OS is Raspbian, which targets ARMv6+VFP,
  whereas Debian `armhf` targets ARMv7 — a Debian-built `armhf` package
  would install on a Raspberry Pi 1/Zero/Zero W but crash there with
  "Illegal instruction". The Raspbian build runs on every Pi and also
  installs on Debian `armhf` (same package names, same ABI; `dpkg-shlibdeps`
  only emits minimum versions both archives satisfy), so the installation
  test runs in both a Raspbian and a `debian:<suite>-slim` `linux/arm/v7`
  container. There is no official Raspbian image on Docker Hub, so the
  workflow creates one per run with `mmdebstrap` from
  `http://raspbian.raspberrypi.com/raspbian` (the mirror Raspberry Pi OS
  itself uses; it offers no HTTPS, integrity comes from the signed
  `InRelease`) and `docker import`s it. Raspbian's archive key is vendored
  as `.github/keys/raspbian-archive-keyring.asc` (fingerprint
  `A0DA38D0D76E8B5D638872819165938D90FDDD2E`, checked by the workflow)
  rather than fetched at build time. GitHub's arm64 runners cannot execute
  32-bit ARM code, so these legs run under QEMU user-mode emulation
  (Ubuntu's `qemu-user-static`, no third-party action) on an amd64
  runner, which makes them several times slower than the native legs
  (timeout 300 instead of 45 minutes).
- **i386** is built for bookworm only: Debian 13 dropped i386 as an
  installable architecture (no kernel, no installer; only a multiarch
  userland for amd64 systems is still built), so there is no Debian 13
  32-bit PC system to target. It runs natively on an amd64 runner.
- Other 32-bit Debian architectures (`armel`, `mipsel`) are not built;
  neither is a target for Raspberry Pi OS, and SvxLink stations on them
  are not a known use case.

The build legs run in parallel with `fail-fast: false`: nothing in them
writes shared state, and an architecture-specific failure (e.g. only in
an emulated leg) should not withhold the healthy legs. Each successful
leg uploads its packages as a short-lived Actions artifact; a single
`publish-daily-deb` job (`if: !cancelled()`) then publishes every leg
that built and passed its installation test, one after the other, into
the GitHub prereleases and the `gh-pages` APT repository (one commit for
all legs), so there is no push race on `gh-pages`. A failed leg still
marks the run as failed. Each leg builds exactly the commit output by the
sync; on the daily schedule the whole build is skipped rather than
rebuilding an unchanged commit (see above). The server build does not
include Qtel or sound files; these are a separate package respectively
must be installed to match the station (see "Packages" below).

Two features that need dependencies not packaged in Debian are built from
source in the same container before the main configure, following the
project's general rule for such cases: use the base OS's package where one
exists and is current enough, build and bundle the rest.

- **RTL-SDR**: direct-USB RTL-SDR support (`HAS_RTLSDR_SUPPORT`) is built
  against the [RTL-SDR Blog fork](https://github.com/rtlsdrblog/rtl-sdr-blog)
  of librtlsdr/rtl_tcp instead of Debian's `librtlsdr-dev`, since the
  distro version is typically too old for current RTL-SDR Blog V3/V4
  dongles. It is installed to `/usr/local` in the build container only,
  then `librtlsdr.so*`, `rtl_tcp`, `rtl_sdr`, `rtl_eeprom` and `rtl_test`
  are copied into the package's own staging tree via a small
  `CPACK_INSTALL_SCRIPT` (`bundle-extra-libs.cmake`, generated inline in
  `build-daily-deb.sh`) so they ship inside the `svxlink` package itself.
  `libusb-1.0-0-dev` still comes from the base OS. The package
  `Conflicts` with Debian's `librtlsdr0`/`rtl-sdr` to avoid both trying to
  own the same files.
- **SipLogic**: the contributed SipLogic logic core
  (`-DWITH_CONTRIB_SIP_LOGIC=ON`) needs `libpjproject`, which is not
  packaged in Debian either. [PJSIP/pjproject](https://github.com/pjsip/pjproject)
  is built from source and installed to `/usr/local` for the same reason,
  but pjproject builds static libraries by default, so `SipLogic.so` links
  it in directly — there is nothing extra to bundle or depend on at
  runtime for it. Its static libraries need `-fPIC` (set via `CFLAGS`/
  `CXXFLAGS` before `./configure`) since they end up linked into
  `SipLogic.so`, a shared object; pjproject does not enable that by
  default.

## Packages

Each leg produces two `.deb` packages from one source tree, following the
same idea as an Arch/AUR split package: build once, then hand-pick each
package's own files rather than shipping everything in one package. CPack
has no per-component packaging set up in this tree (that would need every
`install()` call across the whole project tagged with a `COMPONENT`), so
Qtel gets its own full second build with `-DUSE_QT=ON` into a private
root, from which only its files are copied into a hand-assembled
`qtel_<version>_<arch>.deb` (`dpkg-deb --build`, not CPack); the main
`svxlink` build is untouched by this and stays `-DUSE_QT=OFF`.

| Package   | Contains |
|-----------|----------|
| `svxlink` | Server components (svxlink, remotetrx, svxreflector, logic cores, Tcl event scripts), including RTL-SDR, SipLogic, GPIOD, Speex/Opus/LADSPA as described above, and a systemd service. No Qtel, no sound packs. |
| `qtel`    | Graphical EchoLink client (Qt6). Needs a desktop environment. `Depends: svxlink (= <same version>)` for the echolib/async shared libraries they have in common; the private `libasyncqt.so` (only built for Qtel) is bundled inside the `qtel` package itself. |

`qtel`'s other runtime dependencies (Qt6, GSM, …) are resolved with
`dpkg-shlibdeps` against a minimal, hand-written `debian/control` rather
than hand-listed, since exact package names shift between suites (e.g.
the "t64" time_t-transition renames affecting trixie but not bookworm);
`--ignore-missing-info` skips echolib/asyncaudio/asynccore, which are not
real Debian packages, relying on the `svxlink` pin instead.

Both packages share the same version string and are published together:
same daily prerelease, same APT repository pool entry for that suite/arch.
The `gh-pages` `index.html` lists every published package with what it
contains (see `publish-apt-repo.sh`) — keep that listing (and this table)
up to date whenever a package's build flags or bundled dependencies
change, in the same change, per the rule in `AGENT.MD`.

Both from-source builds run once per matrix leg (same container, before
the main `cmake` configure), so they follow the same architecture/suite as
the rest of that leg automatically. `dpkg-deb -c` on the built package is
checked for `librtlsdr.so` and `SipLogic.so` right after the build, and the
installation test additionally runs `ldd` on the `svxlink` binary and on
`SipLogic.so` to catch a broken or missing link at the earliest point.

The Debian version follows the scheme
`26.05.1+daily20260912.42.1.g0123456789ab-1~trixie`: project version from
`src/versions`, UTC date, workflow run number, attempt, commit short hash
and target suite. It increases within a project version with every new
daily run; the next higher project version sorts after it. `Release` as
the CMake build type only means optimized machine code, not a stable
release.

After package inspection and an installation test in a fresh container of
the respective suite (`.github/scripts/test-daily-deb.sh`), each leg
uploads its `.deb` files, `SHA256SUMS-<suite>-<arch>` and metadata as an Actions
artifact (3-day retention, only a hand-over to `publish-daily-deb`).
That job (via `.github/scripts/publish-packages.sh`, shared with the
release builds) uploads them with the GitHub CLI into the daily prerelease of
the respective suite: the tag is derived from the version, which carries
the suite but not the architecture, so all architectures of one suite
share one prerelease (titled `Daily <version> — <suite>`), and the
checksum file is named per suite/architecture so they do not overwrite
each other. The tag points to the built commit (or, if that commit's
`.github/workflows/` files differ from the default branch's, e.g. for a
manual build of an older commit, to the default branch — see the
`release-<tag>` note under "Upstream release packages" for why). No prerelease is marked as
"Latest". There is no build cache; temporary files are removed after the
upload. A failed leg uploads no artifact and therefore publishes
nothing. `cleanup-old-releases` and `deploy-pages` still run afterwards
(`if: always()`) regardless, to publish/prune whatever legs did
complete — see "Retention" below.

The `.github/scripts/build-daily-deb.sh` script determines the
architecture (`dpkg --print-architecture`), distribution codename
(`VERSION_CODENAME` from `/etc/os-release`) and base distribution (`ID`,
`debian` or `raspbian`) from the respective build container itself
instead of hardcoding them. An additional matrix entry for a further
Raspberry Pi OS/Debian/Ubuntu version or architecture therefore simply
calls the same script with a different `platform`/base image and a
runner matching that architecture (e.g. `ubuntu:24.04` for Ubuntu
Noble); the version scheme, conflicts and the subsequent publishing adapt
automatically.

## Upstream release packages

Besides the daily builds, `.github/workflows/build-releases.yml` packages
the official upstream releases: every published (non-draft,
non-prerelease) `sm0svx/svxlink` release whose tag is numeric with major
version 26 or newer (currently `26.05`, `26.05.1`, `26.05.2`; older
releases are deliberately not built), for every target in
`.github/build-targets.json`.

- **Source:** the unmodified upstream release tag (the same content as
  that release's source tgz/zip), checked out from `sm0svx/svxlink`. None
  of this fork's source changes are applied; only the build settings
  (RTL-SDR Blog librtlsdr, SipLogic with PJSIP, GPIOD, Speex/Opus/LADSPA,
  systemd, the separate `qtel` package) are the same as for the daily
  packages. Qt6 needs C++17 while upstream forces `--std=c++11` into the
  global flags (and overwrites `CMAKE_CXX_FLAGS_RELEASE` with a plain
  `set()`), so the qtel build uses a tiny `CMAKE_CXX_COMPILER_LAUNCHER`
  that appends `-std=c++17` as the last argument of every C++ compile
  (the last `-std` wins for gcc) instead of patching the source. The build checks that `src/versions`
  of the checked-out tree really says `PROJECT=<tag>`.
- **Version:** `<tag>-1~<suite>`, e.g. `26.05.2-1~trixie`. This sorts
  below the daily builds of the same or later code (`26.05.2.99.0+daily…`).
- **Publishing:** one GitHub release `release-<tag>` per upstream release
  (not a prerelease; the highest version is marked "Latest"), holding
  the packages of all suites/architectures; and the APT repository's
  `release` component
  (`dists/<suite>/release/…`, `pool/<suite>/release/…`). Neither is ever
  pruned: `prune-daily-releases.sh` only touches `daily-*` releases, and
  `publish-apt-repo.sh` only prunes files carrying a `+daily<date>`
  version marker. The `release-<tag>` tag points to this repository's
  default branch at publishing time, not to the upstream tag's commit:
  the `GITHUB_TOKEN` may only create a tag on a commit whose
  `.github/workflows/` files match the default branch's (otherwise
  HTTP 403, as that would count as changing workflows), and upstream
  commits carry upstream's own workflows. The release notes name the
  upstream tag and its exact commit.
- **When:** the workflow runs daily at 05:47 UTC (after the upstream sync)
  and on manual dispatch. Its `plan` job (`plan-release-builds.sh`)
  compares the upstream releases against the `release` pool on
  `gh-pages` and builds only what is missing — the existing releases
  once, then each newly published upstream release, and, for all kept
  releases, any target added to `build-targets.json` later. On a normal
  day it builds nothing. A release package is never rebuilt once it is
  in the pool, so a given version always means the same bits.
- **Failures:** a combination whose build failed or timed out within the
  last 7 days (taken from this workflow's own run history, by job name
  `<tag> <suite>/<arch>`) is not retried automatically, since an
  emulated armhf build takes hours and a release that does not build on
  some target usually keeps failing; dispatch the workflow with
  `retry_failed` to retry it earlier. Other combinations are published
  regardless (`fail-fast: false`).

Users choose per system: `main` for the daily builds or `release` for
the upstream releases. Enabling both makes apt prefer the daily builds,
since they always carry the higher version. Both workflows push to the
same `gh-pages` branch; `publish-packages.sh` re-clones and re-applies its
packages if a push is rejected because the other one pushed in between,
and both Pages deploy jobs share one concurrency group.

## APT repository on GitHub Pages

After the daily prerelease, `publish-daily-deb` additionally publishes
every leg's packages into a shared APT repository, committed to the `gh-pages` branch,
so that all currently maintained versions can be fetched with `apt
install` and updated automatically (see "Installing on Raspberry Pi OS
and Debian" below). The `gh-pages` branch itself is only used as the
persistent, incremental data store the retention/pool logic reads and
writes; it is not what GitHub serves directly. A separate `deploy-pages`
job (`needs: publish-daily-deb`, `if: always()`) runs once per workflow
run after publishing finishes, checks out that branch's current content and publishes
it via `actions/configure-pages`, `actions/upload-pages-artifact` and
`actions/deploy-pages` — the `GitHub Actions` Pages source, not the
classic `Deploy from a branch` one. `configure-pages` creates the Pages
site if none exists yet, but does **not** switch an *already existing*
branch-based ("legacy") site to the workflow source, and that switch
cannot be automated in the workflow either: changing a Pages site's
`build_type` needs repo admin rights, which the `GITHUB_TOKEN`'s `pages`
permission does not grant (confirmed via "Resource not accessible by
integration", HTTP 403) even with `pages: write` declared — that scope
only covers creating deployments, not reconfiguring the site. See
"Setup" below for the one-time manual switch this depends on if Pages
was ever set up as `Deploy from a branch` before. This deliberately
avoids `Deploy from a branch` in the first place: that source makes
GitHub run its own internal `pages-build-deployment` workflow outside
this repository (not a file under `.github/workflows/`,
and triggered on every push to the Pages source branch regardless of
`build_type` — it kept running alongside `deploy-pages` here until the
explicit switch above was added), which has been observed pinned to a
deprecated Node.js runtime with no way for us to update it — seeing that
again is the signal something has regressed here.

Layout of the repository, separated by suite (Debian/Ubuntu codename) and
architecture — this matches the usual Debian repository layout (as
produced by e.g. `reprepro`) and can therefore be extended losslessly with
further Raspberry Pi OS/Debian/Ubuntu versions and architectures without
touching existing paths:

```
dists/<suite>/InRelease
dists/<suite>/Release
dists/<suite>/Release.gpg
dists/<suite>/<component>/binary-<arch>/Packages[.gz]
pool/<suite>/<component>/<letter>/<package-name>/<package>.deb
pubkey.gpg                                   # public signing key
```

`<suite>` is the distribution codename (currently `bookworm` and `trixie`,
see matrix above), `<component>` either `main` (daily builds) or
`release` (upstream releases, see "Upstream release packages"), `<arch>` the Debian architecture (currently `arm64`,
`amd64`, `armhf` and, for bookworm only, `i386`). A later build for a
further architecture or a new Debian version simply adds a further
`binary-<arch>` or `dists/<new suite>/...` branch; existing suites/architectures remain unchanged. Separate paths are
necessary
because a `.deb` only ever matches exactly one distribution version and
architecture, and APT clients only load packages from the
`dists/<suite>/.../binary-<arch>` branch matching them.

The `.github/scripts/publish-apt-repo.sh` script handles placing the file
in the pool, rebuilding `Packages`/`Packages.gz` with `dpkg-scanpackages`,
rebuilding and signing `Release`/`InRelease` with `apt-ftparchive` and
`gpg` respectively, and keeping the public key available as `pubkey.gpg`.
So that the `gh-pages` branch does not grow without bound, older `.deb`
files are pruned per package/suite/architecture using the same retention
policy as the daily releases (see "Retention" below) before rebuilding
the index. A failed build does not publish anything here either.

### Start page and translations

The repository's start page (`index.html`) is rendered by
`render-start-page.sh` (run by `publish-apt-repo.sh` after every package
publish, and by the `Refresh start page` workflow whenever only the
templates under `.github/pages/` change) from the English master template
`.github/pages/index.html.in`, filling in only what depends on the
repository state (the supported-systems table per component, a row for
any package not described in the template, the language links). The
same page is also published in the European languages listed in
`.github/pages/languages.tsv` — the 24 official EU languages plus the
national languages of the other European states (Norwegian, Icelandic,
Albanian, Serbian, Bosnian, Macedonian, Ukrainian, Belarusian, Russian,
Turkish, Luxembourgish, Catalan, Romansh) — as `index.<lang>.html`, from
the translated templates in `.github/pages/i18n/`. Every page links to
all languages (and declares them via `hreflang`); every translated page
shows a notice in its own language that it is an AI-generated
translation, with a link to the English original. The generator inserts
that notice itself (text from `languages.tsv`), so it cannot be left out.

The translations must be updated together with every change to the
English template (rule in `AGENT.MD`). Each translation records the
SHA-256 of the English template it was made from
(`<meta name="source-sha256">`); `bash .github/scripts/check-translations.sh`
lists which ones are current, outdated or missing and prints the hash to
use. The `Check start page translations` workflow runs it with
`--strict` on every change under `.github/pages/` and fails if any
translation is behind; publishing still renders an outdated translation
(with a workflow warning) rather than blocking package publication.
`.github/.gitattributes` keeps LF line endings for everything under
`.github/`, so the hash is the same in every checkout.

### Signing key

For APT to trust the repository, `Release` is signed with a GPG key
(`Release.gpg` as a detached signature, and `InRelease` as an inline
signed variant; APT accepts both forms). The private key exists only as
the repository secret **APT_SIGNING_KEY** (ASCII-armored,
`gpg --export-secret-keys --armor <fingerprint>`) and is imported and used
during the workflow run, then removed again from the runner's `GNUPGHOME`
at the end. The key was deliberately generated without a passphrase so
that signing works unattended in CI; the only protection is therefore
access control on the GitHub secret. Anyone who prefers a passphrase must
extend the import step in the workflow with
`--pinentry-mode loopback --passphrase-fd 0` and an additional secret for
the passphrase.

A new key is generated locally, for example, with:

```sh
gpg --batch --gen-key <<'EOF'
%no-protection
Key-Type: RSA
Key-Length: 4096
Key-Usage: sign
Name-Real: SvxLink DB9CR APT Repository
Name-Comment: Daily package signing key
Expire-Date: 3y
%commit
EOF
gpg --list-secret-keys --keyid-format=long "SvxLink DB9CR APT Repository"
```

Then store the private key as a secret (insert the fingerprint from the
previous output) and delete the local export file afterwards:

```sh
gpg --export-secret-keys --armor <FINGERPRINT> > apt-signing-key-private.asc
gh secret set APT_SIGNING_KEY --repo criede/svxlink-db9cr < apt-signing-key-private.asc
rm apt-signing-key-private.asc
```

The public key does not need to be stored separately: the workflow
exports it freshly from the imported private key on every run to
`pubkey.gpg` in the repository root. A key change (e.g. after expiry or
compromise) automatically produces a new `pubkey.gpg`; users then need to
import the key again (see below).

### Retention

Both the daily GitHub prereleases and the packages kept in the APT
repository's pool follow the same grandfather-father-son retention
policy, implemented once in `.github/scripts/gfs-retention.sh` and
applied independently per series (per suite for releases; per
package/suite/architecture for the pool) so every currently maintained
suite always keeps its own recent history. Applying the same policy to
both keeps the pool from growing without bound while still matching what
the release history shows — `apt install pkg=<old-version>` only works
for as long as that exact version is still listed in the suite's
`Packages` index, so a version dropped from the pool is a version that
has genuinely aged out, not one arbitrarily pruned more aggressively
than its release was:

| Age                | Kept                          |
|--------------------|--------------------------------|
| < 1 week            | every build                    |
| 1 week – 1 month    | the newest build per ISO week  |
| 1 month – 1 year    | the newest build per month     |
| ≥ 1 year            | nothing                        |

"Every build" in the under-a-week row is literal: `gfs-retention.sh`
buckets that range per *entry*, not per day, so several builds sharing
the exact same date (repeated `workflow_dispatch` runs on one day,
manual testing, a retry) are all kept rather than collapsed to one.
An earlier version bucketed by day even there, comparing dates to decide
which of two same-day entries was "newest" — a comparison that can never
tell two identical dates apart, so it silently kept whichever entry was
processed first and dropped every other same-day build, including same-day
re-runs meant to supersede a broken one. The weekly/monthly rows still
bucket by ISO week / calendar month and so retain that same limitation
for entries that happen to share an exact date within a week or month,
but that only matters at all for a suite with more than one build on the
same calendar day, which does not happen in normal single-run-per-day
operation.

For the pool, pruning happens as part of `publish-apt-repo.sh` on every
run, right after the new package is added and before the index is
rebuilt. For releases, a separate `cleanup-old-releases` job runs once
per workflow run, after `publish-daily-deb` has finished
(`if: always()`, so it still runs even if a leg failed); it lists all
`daily-*` releases, groups them by suite, and deletes each release
together with its tag (`gh release delete <tag> --yes --cleanup-tag`) if
it falls outside the window for its suite. Both derive the build date
the same way, from the `+daily<YYYYMMDD>` marker in the version string;
anything that does not match this shape is left untouched rather than
risk deleting something unrelated. Because both run the identical policy
independently but off the same dates, a version disappearing from the
pool and its release disappearing from the Releases page happen
together, not one before the other.

## Installing on Raspberry Pi OS and Debian

Once GitHub Pages has been deployed at least once (see "Setup" — no manual
enabling needed), the repository can be added. The commands are identical for all supported
systems; only the codename in the repository line differs:

| Operating system                   | Codename    |
|-------------------------------------|-------------|
| Raspberry Pi OS Trixie (64-bit and 32-bit)   | `trixie`    |
| Raspberry Pi OS Bookworm (64-bit and 32-bit) | `bookworm`  |
| Debian 13 (Trixie)                  | `trixie`    |
| Debian 12 (Bookworm)                | `bookworm`  |

Both codenames are currently maintained for `arm64` (Raspberry Pi OS,
Debian), `amd64` (Debian on Intel/AMD PCs and servers) and `armhf`
(32-bit Raspberry Pi OS on every Pi model including Pi 1/Zero/Zero W,
Debian armhf); `i386` (32-bit PCs) is available for Debian 12 only, as
Debian 13 no longer supports installing i386 systems. See the matrix in
the "Daily package" section above.

### Choosing a component: `main` or `release`

The repository offers two components; the choice is made per system, in
the repository line below:

| Component | Contains | Source | Updates via `apt upgrade` | Kept |
|-----------|----------|--------|----------------------------|------|
| `main`    | Daily development builds | This fork's `master` (upstream `master` plus the local changes listed in `CHANGELOG.MD`) | Every new daily build | Retention window (see "Retention") |
| `release` | Official upstream SvxLink releases, 26.05 and newer | The unmodified upstream release tag | Each new upstream release | Forever |

Both components contain the same packages (`svxlink`, `qtel`) with the
same build settings and features (RTL-SDR, SipLogic, GPIOD, Speex/Opus/
LADSPA, systemd service) for the same suites/architectures. The
differences come from the source: `release` packages contain none of
this fork's source changes (e.g. the TCL scripts are not dpkg conffiles
there, see below) and only change when upstream publishes a release.

Use `release` for a station that should run a known, released version;
use `main` to follow current development. Configure only one of them:
with both enabled, apt always prefers `main`, since a daily build always
carries a higher version than the release it is based on (e.g.
`26.05.2.99.0+daily…` > `26.05.2-1~trixie`).

On the target system, pick up the matching codename automatically and set
up the repository:

```sh
# Import the public signing key
curl -fsSL https://criede.github.io/svxlink-db9cr/pubkey.gpg | \
  sudo gpg --dearmor -o /usr/share/keyrings/svxlink-db9cr.gpg

# Add the repository source, restricted to the key and to the local
# codename/architecture combination. Component: "main" for the daily
# builds, "release" for the official upstream releases (26.05 and newer).
component=main
codename=$(sed -n 's/^VERSION_CODENAME=//p' /etc/os-release | tr -d '"')
arch=$(dpkg --print-architecture)
echo "deb [signed-by=/usr/share/keyrings/svxlink-db9cr.gpg arch=${arch}] https://criede.github.io/svxlink-db9cr ${codename} ${component}" | \
  sudo tee /etc/apt/sources.list.d/svxlink-db9cr.list

sudo apt update
sudo apt install svxlink

# Mandatory before the first start: configure the station, radio and audio.
# The packaged file is only a template and must be adapted to the setup.
sudo editor /etc/svxlink/svxlink.conf

sudo systemctl daemon-reload
sudo systemctl enable --now svxlink.service
systemctl status svxlink.service
journalctl -u svxlink.service -f

# Optional graphical EchoLink client (needs a desktop environment):
# sudo apt install qtel
```

After changing `/etc/svxlink/svxlink.conf` or a module config under
`/etc/svxlink/svxlink.d/` on a running station, `sudo systemctl reload
svxlink.service` applies it (sends `SIGHUP`, which SvxLink re-reads its
configuration on) without dropping an active session; fall back to
`sudo systemctl restart svxlink.service` if a change does not seem to
take effect (loaded logic cores/modules or sound devices may need a full
restart).

If the detected codename is not (yet) part of the matrix, `apt update`
reports a 404 for the affected source; in that case, either set the
codename in `/etc/apt/sources.list.d/svxlink-db9cr.list` manually to one
of the values listed above, or wait for the matrix to be extended.

After that, a regular `sudo apt upgrade` automatically delivers the
latest version of the chosen component for the installed system: the
newest daily build (`main`) or the newest upstream release (`release`).
Daily builds are development builds, not stable releases — see the notes
above on scope and test coverage.

### Switching between `main` and `release`

Change the component in the repository line and update. Moving from
`main` to `release` is a downgrade (the daily builds carry the higher
version), so request the release version explicitly:

```sh
sudo sed -i 's/ main$/ release/' /etc/apt/sources.list.d/svxlink-db9cr.list
sudo apt update
apt list -a svxlink   # shows the release versions now available
sudo apt install svxlink=26.05.2-1~trixie qtel=26.05.2-1~trixie   # qtel only if installed
```

Moving from `release` to `main` is a normal upgrade:

```sh
sudo sed -i 's/ release$/ main/' /etc/apt/sources.list.d/svxlink-db9cr.list
sudo apt update && sudo apt upgrade
```

The configuration under `/etc/svxlink` is kept either way (dpkg
conffiles). After switching to `release`, review local edits to the TCL
scripts under `/usr/share/svxlink`: they are conffiles only in `main`
packages (see below), so a `release` package may replace them.

### Rolling back to an older build

A version stays installable for as long as its retention window has not
expired (see "Retention" above — daily for a week, weekly for a month,
monthly for a year), so a recent bad daily build can usually be rolled
back to an earlier one. List the available versions, then install a
specific one explicitly (`apt` will offer to downgrade):

```sh
apt list -a svxlink   # substitute qtel to roll that package back instead
sudo apt install svxlink=26.05.1+daily20260910.5.1.gabcdef012345-1~trixie
```

With the `release` component, every published upstream release stays
installable permanently, so going back to an earlier release works the
same way, e.g. `sudo apt install svxlink=26.05.1-1~trixie`.

To pin a package at that version so `apt upgrade` does not pull it
forward again until you decide to, add `apt-mark hold svxlink` (and
`apt-mark unhold svxlink` later to resume automatic updates).

In the `main` (daily) packages, the TCL files under `/usr/share/svxlink` (`events.tcl`, `events.d/*.tcl`,
`modules.d/*.tcl`) are installed as dpkg `conffiles`, just like the `.conf`
files under `/etc` (`install_files_if_not_exists` in the respective
`CMakeLists.txt`, analogous to the existing `install_if_not_exists`
function for configuration files). If an administrator edits one of these
files directly, a later package upgrade no longer silently overwrites the
change: dpkg detects the local deviation from the last shipped state and
asks during the upgrade (or keeps the local state on unattended upgrades),
instead of silently replacing the file. Unmodified files continue to be
updated normally. This does not affect the already recommended path via
`events.d/local/*.tcl` for own additions, since new files not shipped by
the package are never touched by dpkg. This is a change of this fork; the
`release` packages, built from unmodified upstream source, install these
TCL files as regular files, so an upgrade there overwrites direct edits
— use `events.d/local/*.tcl` for local changes on `release` systems.

What dpkg actually does with a conffile on upgrade, depending on whether
the admin and/or upstream touched it since the last install:

- **Neither changed it**: the new version is installed silently.
- **Only the admin changed it** (upstream shipped the same content as
  before): the local edit is left alone; nothing to merge.
- **Both changed it** (the real conflict): on an interactive
  `apt install`/`apt upgrade`, dpkg asks whether to keep the local
  version or install the maintainer's. **Either way nothing is lost**: if
  the local version is kept (the default), the new shipped version is
  written next to it as `<file>.dpkg-dist` for later manual review/merge
  (`diff events.tcl events.tcl.dpkg-dist`); if the new version is
  installed instead, the local edit is saved as `<file>.dpkg-old`. On
  unattended upgrades (`unattended-upgrades` typically runs with
  `--force-confdef --force-confold`), the local version is kept
  automatically and `.dpkg-dist` is still written, without blocking the
  upgrade. Stray `.dpkg-dist` files can be found with
  `find /usr/share/svxlink -name '*.dpkg-dist'`.

## Setup

1. Push the workflows to the GitHub repository's default branch.
2. Enable GitHub Actions in the repository, if not already done.
3. Create the repository secret **APT_SIGNING_KEY** (see "Signing key"
   above) — without this secret, the `publish-daily-deb` job fails while signing
   the APT repository.
4. If GitHub Pages has never been enabled for this repository, no
   further action is needed — `actions/configure-pages` creates it with
   the `GitHub Actions` source on the first `deploy-pages` run. If Pages
   was previously set up with the classic **Deploy from a branch**
   source (as this repository's was), switch it once, with an account
   that has admin rights on the repository (the workflow's own
   `GITHUB_TOKEN` cannot do this — see "APT repository on GitHub Pages"
   above): `gh api -X PUT repos/<owner>/<repo>/pages -f build_type=workflow`,
   or under **Settings → Pages → Build and deployment → Source** in the
   web UI.
5. Start a first run under **Actions → Sync upstream → Run workflow**
   (or, to build/publish without going through the upstream merge,
   **Actions → Build and publish → Run workflow** directly — note that a
   `source_sha` typed in there must be the full 40-character commit SHA,
   not an abbreviated one).

If a `github-pages` deployment **environment** already exists in the
repository (e.g. left over from a previous `Deploy from a branch` setup)
with a custom deployment branch policy, that policy is not something
`configure-pages` touches, and the run fails at the `deploy-pages` job
with "Branch ... is not allowed to deploy to github-pages due to
environment protection rules." Fix once under **Settings → Environments
→ github-pages → Deployment branches and tags**: add the branch that
`build-and-publish.yml` actually runs on (`master`, via `sync-upstream.yml`
or a direct dispatch) to the allowed list, or via
`gh api -X POST repos/<owner>/<repo>/environments/github-pages/deployment-branch-policies -f name=master`.
A repository where this environment does not exist yet is unaffected.

By default, the workflow uses the automatically provided `GITHUB_TOKEN`
with `contents: write`. Branch rules must allow this direct push, also for
the `gh-pages` branch. Pushes with this token do not trigger further push
workflows.

So that changes to `.github/workflows/` can also be taken over, set up a
repository secret **UPSTREAM_SYNC_TOKEN** if needed: a fine-grained
personal access token restricted to this repository with **Contents: Read
and write** and **Workflows: Read and write**. The workflow uses this
secret preferentially. Without sufficient permission, GitHub can reject
the push with workflow changes. A PAT can also trigger subsequent push
workflows. Store token values exclusively in GitHub secrets.

GitHub can delay scheduled runs and disables scheduled workflows in public
repositories after 60 days without repository activity. On forks,
scheduled workflows may initially be disabled. Re-enable them under
**Actions** if needed. The schedule requires the file to be on the default
branch.

Only a push (by anyone or anything, including `github-actions[bot]`) counts
as activity for that 60-day clock — a scheduled workflow simply running,
without pushing anything, does not reset it. Since the build above is
skipped whenever upstream has nothing new, this repository could
otherwise go quiet for as long as `sm0svx/svxlink` does. To guard against
that, the "Merge upstream master" step pushes a trivial heartbeat commit
(updates `.github/HEARTBEAT` with the current timestamp, no other effect)
whenever `master`'s last commit is 25 or more days old — comfortably
before the 60-day deadline, and only on days there was otherwise nothing
to push.

## Sources

- [GitHub: Events that trigger workflows](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows)
- [GitHub: GITHUB_TOKEN](https://docs.github.com/en/actions/concepts/security/github_token)
- [GitHub: Permissions for workflow changes](https://github.github.com/gh-aw/reference/safe-outputs-pull-requests/)
- [GitHub Pages: Publishing with a custom GitHub Actions workflow](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site#publishing-with-a-custom-github-actions-workflow)
- [GitHub Actions: Reusing workflows](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows)
- [Debian Wiki: SecureApt](https://wiki.debian.org/SecureApt)
- [Debian Repository Format](https://wiki.debian.org/DebianRepository/Format)
- [Debian Policy Manual: conffiles](https://www.debian.org/doc/debian-policy/ch-files.html#configuration-files)
