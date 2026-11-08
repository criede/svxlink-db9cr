# Tasks

Open tasks for svxlink-db9cr. The following items serve as an initial plan.

## Project basics

- [ ] Document the goal and scope of the DB9CR-specific customizations.
- [ ] Describe the Debian installation and required dependencies in `Debian.md`.
- [ ] Verify the build against `INSTALL.adoc` in a suitable Linux environment.

## Configuration and operation

- [ ] Determine the required SvxLink modules and station configuration.
- [ ] Document local customizations and anonymized example configurations.
- [ ] Define a test procedure for audio, PTT and DTMF.

## Documentation

- [x] Publish the daily Debian package for Raspberry Pi OS arm64 directly as a prerelease.
- [x] Build the daily packages for the 32-bit variants too (armhf via Raspbian, i386 for bookworm).
- [x] Package the upstream releases (26.05 and newer) automatically, APT component `release`.
- [ ] Verify the first run of `build-releases.yml` (backlog of 26.05, 26.05.1, 26.05.2 on all targets).
- [ ] Verify the first CI run of the 32-bit legs (QEMU build time vs. the 300-minute timeout, Raspbian/Debian armhf installation tests).
- [x] Implement the daily upstream sync as a GitHub Actions workflow.
- [ ] Continuously record completed changes in `CHANGELOG.MD`.
- [ ] Check off tasks on completion and describe new tasks concretely.
