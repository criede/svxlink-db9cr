# Changelog

This log records changes to svxlink-db9cr since its introduction. The
project's existing release notes are located under `src/doc/`.

## Unreleased

### Changed

- The APT repository pool now keeps every published version indefinitely
  instead of pruning it with the same grandfather-father-son policy as
  the daily GitHub prereleases: `apt install pkg=<old-version>` only
  works for as long as that version is still listed in the pool, so it
  is the one place old builds need to stay reachable to actually roll
  back to them. The daily prereleases keep the GFS policy unchanged.
- Fixed a `gfs-retention.sh` bug where several builds sharing the exact
  same date (repeated manual `workflow_dispatch` runs on one day, a
  retry) were collapsed down to just one, since the "keep the newest per
  bucket" comparison could never tell two identical dates apart and
  silently kept whichever entry it processed first. Builds under a week
  old are no longer bucketed by day at all -- every one of them is kept,
  matching what the policy already claimed to do. This had been quietly
  losing same-day rebuilds' releases and (before the pool retention
  change above) pool packages during this session's testing.
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
