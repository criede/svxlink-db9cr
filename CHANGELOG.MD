# Changelog

This log records changes to svxlink-db9cr since its introduction. The
project's existing release notes are located under `src/doc/`.

## Unreleased

### Changed

- Upstream sync permanently excludes changes to `.github/workflows/`;
  own workflow files are fully preserved, even on fast-forwards.
- Upstream CodeQL disabled in the own repository: automatic triggers
  removed and execution restricted to the upstream repository.
- Project rule: use only currently maintained Node.js runtimes in
  workflows, including the internal runtime of included actions.
- CodeQL workflow switched to Checkout v6 and CodeQL Action v4 with
  Node.js 24, with permissions to upload the analysis results set explicitly.

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
  can be added later; old versions are pruned per package/suite/architecture.
  The repository's `index.html` is a self-contained quickstart (codename/
  architecture auto-detection, supported-systems table) rather than a link
  to the maintainer-facing `UPSTREAM-SYNC.MD`.
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
