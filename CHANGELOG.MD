# Changelog

This log records changes to svxlink-db9cr since its introduction. The
project's existing release notes are located under `src/doc/`.

## Unreleased

### Changed

- Package versions now end in the Debian major version (`~deb12`,
  `~deb13`) instead of the codename (`~bookworm`, `~trixie`), like Debian's
  backports: dpkg sorts codenames alphabetically, so after an upgrade to
  Debian 14 (`~forky` < `~trixie`) apt would have kept the old suite's
  package. The number comes from the build container's `VERSION_ID` and is
  checked against the new `debian_major` field of each target in
  `.github/build-targets.json`. Release packages use a Debian revision from
  the new `.github/scripts/release-debian-revision`, now `2`, so that
  `26.05.2-2~deb13` sorts above the earlier `26.05.2-1~trixie`; all
  releases are built once more under the new versions. Daily release tags
  of both schemes share one retention series (`prune-daily-releases.sh`);
  the planning and publish steps check the new versions. Example versions
  in UPSTREAM-SYNC.MD and on the start page (all languages) updated.

- Security hardening of the packaging and publishing pipeline:
  - `postinst` no longer follows symlinks when changing the owner of the
    state directories (a symlinked directory planted by the `svxlink` user
    could otherwise hand e.g. `/etc` to it on the next upgrade); CPack's
    plain `chown` lines are rewritten to act only on symlink-free paths, with
    `-h`. The installation test checks this with a planted symlink.
  - The third-party sources bundled into the packages (RTL-SDR Blog
    librtlsdr, PJSIP/pjproject) are pinned to reviewed commits instead of
    being built from their moving default branches.
  - The RTL-SDR udev rule is generated from validated USB IDs only; no
    upstream rule text (which could carry e.g. a `RUN+=` key executed as
    root) is copied into the package.
  - The publish jobs validate every build artifact against what the
    workflow itself decided (kind, suite, architecture, tag, source
    commit), accept only the `svxlink` and `qtel` packages with matching
    control fields, write the release notes themselves, take their scripts
    only from the workflow's own commit (never from a dispatched
    `source_sha`), and refuse to sign with any key but the pinned one.
    Build outputs with symlinks are rejected before upload.
  - The quickstart imports only the signing key with the published
    fingerprint (start page in all languages, README, UPSTREAM-SYNC.MD).
- `README.adoc` links https://github.com/criede/openelp (packaged OpenELP
  EchoLink proxy fork with SvxLink-protecting security fixes) under
  "Resources".
- RTL-SDR direct USB access now works for the `svxlink` service: the
  package ships `/usr/lib/udev/rules.d/60-svxlink-rtlsdr.rules` (generated
  from the RTL-SDR Blog fork's rules, group `svxlink` plus `uaccess`),
  since conflicting with Debian's `librtlsdr0` also removed its udev rule
  and the service runs as the unprivileged user `svxlink`. `postinst`
  reloads udev; the build and installation test check the rule. Package
  description on the start page (all languages) updated.
- `README.adoc` starts with a box explaining this repository: an
  automatically tracking fork of sm0svx/svxlink whose only purpose is
  building packages, the architectures built, and where to get them (APT
  repository with its quickstart, GitHub Releases).
- `README.adoc` links the APT repository quickstart under "Resources"
  (https://criede.github.io/svxlink-db9cr/#quickstart); the quickstart
  heading on the start page (all languages) got the anchor `quickstart`.
- All start page translations address the reader the way radio amateurs
  address each other: informally, second person singular (du/tu/tú/je/
  ty/ты, ...), never formal or plural forms; recorded in the translation
  rule in `AGENT.MD`.
- The quickstart commands (start page in all languages, UPSTREAM-SYNC.MD)
  now default to the `release` component (upstream releases) instead of
  `main` (daily builds).
- The APT repository start page is now available in all European
  languages (24 official EU languages plus Norwegian, Icelandic,
  Albanian, Serbian, Bosnian, Macedonian, Ukrainian, Belarusian, Russian,
  Turkish, Luxembourgish, Catalan, Romansh) as `index.<lang>.html`, with
  language links on every page and a notice on every translated page
  that it is an AI-generated translation. It is rendered from templates
  in `.github/pages/` instead of a heredoc in `publish-apt-repo.sh`;
  translations record the hash of the English template they were made
  from, `check-translations.sh` and a new `Check start page translations`
  workflow flag outdated ones, and `AGENT.MD` requires updating all
  translations with every change to the English page.
- Start page rendering moved to `render-start-page.sh`; a new `Refresh
  start page` workflow re-renders and deploys it when only the page
  templates change, without waiting for a package build.
- Fixed the start page's architecture columns showing every value twice,
  and the page generation aborting (and with it the whole APT publish)
  for a suite without a `release` component yet.
- Packages of the official upstream SvxLink releases: the new
  `build-releases.yml` workflow builds every upstream release from 26.05
  on (currently 26.05, 26.05.1, 26.05.2) from the unmodified upstream
  release tag, with the same build settings and targets as the daily
  packages, and from then on each newly published upstream release
  automatically. They are published as GitHub releases `release-<tag>`
  and in a new APT component `release` (alongside `main` for the daily
  builds), and are never pruned. Only missing combinations are built;
  recently failed ones are retried after 7 days or on manual dispatch.
- The per-target build steps moved into the reusable workflow
  `build-deb.yml`, the target list into `.github/build-targets.json`, and
  publishing into `.github/scripts/publish-packages.sh`, all shared by the
  daily and the release builds. Publishing retries on a rejected
  `gh-pages` push, and both Pages deploy jobs share a concurrency group.
- The qtel build now forces `-std=c++17` through a tiny compiler launcher (`CMAKE_CXX_COMPILER_LAUNCHER`), so
  Qt6 builds without source patches (needed for unmodified upstream tags).
- Checksum files in GitHub releases are named `SHA256SUMS-<suite>-<arch>`.
- GitHub release tags point to the build commit only if its
  `.github/workflows/` files match the default branch's, otherwise to the
  default branch: the `GITHUB_TOKEN` (no `workflows` permission) gets
  HTTP 403 when creating a tag on a commit with different workflows. This
  always applies to upstream release tag commits (`release-<tag>`) and to
  manual builds of older commits; the release notes name the exact
  source commit.
- Documented choosing between the APT components `main` (daily) and
  `release` (upstream releases), switching between them, rolling back to
  an earlier release, and that the TCL scripts are dpkg conffiles only in
  `main` packages (UPSTREAM-SYNC.MD and the repository's `index.html`).
- Raspbian build image: explicitly include `apt` (only "important" in
  Raspbian bookworm, so missing from minbase), set `PATH` on the
  imported image, and give the build keyring a name that does not clash
  with the `raspbian-archive-keyring` package's conffile.
- The APT repository's `index.html` explains both components and lists
  architectures per component; it had also lost its "Signing key"
  heading in the 32-bit change, now restored.
- Fixed daily builds aborting silently since 2026-10-10: after its 26.05.2
  release upstream set `PROJECT=master` in `src/versions`, which the
  version check rejected, so no package was published after 2026-09-13.
  When `PROJECT` is not numeric, the build now uses the highest numeric
  `PROJECT` value from the git history of `src/versions` (currently
  `26.05.2.99.0`) and logs that it did so.
- Daily packages are now also built for the 32-bit variants of the
  supported systems: `armhf` for bookworm and trixie (32-bit Raspberry Pi
  OS and Debian armhf) and `i386` for bookworm (Debian 12 on 32-bit PCs;
  Debian 13 no longer supports installing i386). `armhf` is built in a
  Raspbian container created per run with `mmdebstrap` (vendored,
  fingerprint-checked archive key) under QEMU user-mode emulation, so the
  packages target ARMv6+VFP and run on every Raspberry Pi including the
  Pi 1/Zero/Zero W; they are installation-tested in both Raspbian and
  Debian armhf. `i386` builds natively on an amd64 runner.
- The build legs now run in parallel with `fail-fast: false` and hand
  their packages over as short-lived Actions artifacts to a single new
  `publish-daily-deb` job, which publishes every successful leg to the
  prereleases and the APT repository in one `gh-pages` commit, replacing
  the previous strictly sequential (`max-parallel: 1`) matrix. The
  checksum file in the shared per-suite prerelease is now named
  `SHA256SUMS-<arch>`, since the architectures of one suite previously
  overwrote each other's `SHA256SUMS`; the prerelease title now names
  the suite only.
- Fixed the installation test's `ldd` checks and the build's
  "required optional feature detected" checks, which could never fail:
  they were written as `! cmd | grep -q ...`, and bash ignores `errexit`
  for a pipeline negated with `!`. The installation test is now a
  separate script, `.github/scripts/test-daily-deb.sh`.
- Fixed a `gfs-retention.sh` bug where several builds sharing the exact
  same date (repeated manual `workflow_dispatch` runs on one day, a
  retry) were collapsed down to just one, since the "keep the newest per
  bucket" comparison could never tell two identical dates apart and
  silently kept whichever entry it processed first. Builds under a week
  old are no longer bucketed by day at all -- every one of them is kept,
  matching what the policy already claimed to do. This had been quietly
  losing same-day rebuilds' releases and pool packages during this
  session's testing, e.g. freezing the `svxlink` pool entry at an early
  test build for the rest of the day. The APT pool and the daily GitHub
  prereleases still both use this same policy, applied independently but
  off the same dates, so a version dropping out of one drops out of the
  other at the same time.
- The APT repository Quickstart now requires editing
  `/etc/svxlink/svxlink.conf` before first start and documents how to enable,
  start, inspect and follow the logs of `svxlink.service` with systemd,
  how to apply a configuration change with `systemctl reload` (SvxLink
  reloads on `SIGHUP`), and how to install/pin an older version for
  rollback.
- Upstream sync permanently excludes changes to `.github/workflows/`;
  own workflow files are fully preserved, even on fast-forwards.
- Upstream CodeQL disabled in the own repository: automatic triggers
  removed and execution restricted to the upstream repository.
- Project rule: use only currently maintained Node.js runtimes in
  workflows, including the internal runtime of included actions.
- CodeQL workflow switched to Checkout v6 and CodeQL Action v4 with
  Node.js 24, with permissions to upload the analysis results set explicitly.

### Changed (continued)

- Split the single `Sync upstream` workflow: `sync-upstream.yml` now only
  merges upstream and then calls the new `build-and-publish.yml` as a
  reusable workflow (`secrets: inherit`). `build-and-publish.yml` carries
  the build/publish/cleanup jobs, has no repository-name guard, accepts
  the commit to build as an input, and is dispatchable standalone — so it
  can be reused as-is in another repository (e.g. upstream).
- GitHub Pages now deploys via a `deploy-pages` job using
  `actions/configure-pages` + `actions/upload-pages-artifact` +
  `actions/deploy-pages` (the `GitHub Actions` Pages source), instead of
  the classic `Deploy from a branch` source. The `gh-pages` branch is now
  only the persistent data store the retention/pool logic reads and
  writes; GitHub no longer serves it directly, and no longer runs its own
  internal `pages-build-deployment` workflow for it, which had been
  observed pinned to a deprecated Node.js version outside our control.
  `configure-pages` does not itself switch an already-existing
  branch-based Pages site to the workflow source, and that switch cannot
  be automated in the workflow either -- it needs repo admin rights the
  `GITHUB_TOKEN`'s `pages` permission does not grant (confirmed via
  "Resource not accessible by integration", HTTP 403); see "Setup" in
  UPSTREAM-SYNC.MD for the one-time manual switch this depends on where
  Pages was previously set up as `Deploy from a branch`.
- Matrix `fail-fast` turned on (was off): a failing leg cancels the
  remaining queued legs immediately instead of repeating the same
  failure across all of them, and marks the run failed.
- The scheduled sync now skips the build entirely when upstream had
  nothing new to merge; a manual run always builds regardless. To
  compensate, a trivial heartbeat commit (`.github/HEARTBEAT`) is pushed
  whenever `master`'s last commit is 25+ days old, since GitHub disables
  scheduled workflows in public repositories after 60 days with no
  repository push, and this repo could otherwise go quiet for as long as
  upstream does.
- `index.html` now links a live GitHub compare view against upstream
  master and `CHANGELOG.MD`, instead of only linking the source repo,
  so what is actually different from upstream is transparent without
  a snapshot here going stale.

### Added

- Native daily build for Raspberry Pi OS and Debian after the sync, built
  as a sequential matrix over all currently maintained Debian releases
  (bookworm, trixie) on both arm64 (Raspberry Pi, native `ubuntu-24.04-arm`
  runners) and amd64 (Intel/AMD, native `ubuntu-24.04` runners, no QEMU),
  with Debian version numbering, an installation test, and direct upload of
  `.deb` and checksums to a GitHub prerelease without Actions artifacts.
- GPG-signed APT repository published to the `gh-pages` branch after each
  daily build, laid out per suite/architecture (`dists/<suite>/...`,
  `pool/<suite>/...`) so further Debian/Ubuntu versions and architectures
  can be added later. The repository's `index.html` is a self-contained
  quickstart (codename/architecture auto-detection, supported-systems
  table) rather than a link to the maintainer-facing `UPSTREAM-SYNC.MD`.
- Shared grandfather-father-son retention (`.github/scripts/gfs-retention.sh`):
  daily builds are kept for a week, weekly for a month, monthly for a year,
  nothing older, applied per suite. Old APT pool packages are pruned as
  part of publishing; old daily GitHub prereleases (and their tags) are
  deleted by a new `cleanup-old-releases` job that runs once per workflow
  run after all `daily-deb` legs finish.
- RTL-SDR Blog fork of librtlsdr/rtl_tcp (V3/V4 dongle support) built from
  source and bundled into the `svxlink` package itself, replacing Debian's
  older `librtlsdr-dev`/`librtlsdr0` (package now `Conflicts` with
  `librtlsdr0`/`rtl-sdr` to avoid file collisions).
- Contributed SipLogic logic core enabled in the daily build
  (`-DWITH_CONTRIB_SIP_LOGIC=ON`), linked against a from-source
  PJSIP/pjproject build (statically linked, nothing to bundle at runtime).
- Separate `qtel` package (Arch/AUR-style split build: one source tree,
  each package hand-assembled from its own install root) alongside
  `svxlink`, published in the same daily prerelease and APT repository
  pool entry, pinned to the same version via `Depends: svxlink (= ...)`.
- `index.html` on the APT repository now lists every published package
  with the features/dependencies built into it, alongside the supported
  systems table.
- TCL event handling scripts (`events.tcl`, `events.d/*.tcl`,
  `modules.d/*.tcl`) are now installed as dpkg conffiles, like the existing
  `.conf` files, so a package upgrade no longer silently overwrites a file
  an admin has edited directly.
- Daily GitHub Actions workflow to merge `sm0svx/svxlink:master` into
  `master`, with manual start and automatic conflict resolution in favor
  of own changes on `master`.
- Setup and operation notes in `.github/UPSTREAM-SYNC.MD`.
- `TODO.MD` with an initial task list for documentation, build and operation.
- `AGENT.MD` with project context and notes for working on the repository.
- `CHANGELOG.MD` for ongoing documentation of changes.
