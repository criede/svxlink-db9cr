# Daily upstream synchronization

This lives across two workflow files with separate responsibilities:

- `.github/workflows/sync-upstream.yml` merges upstream, then calls the
  other workflow. Specific to this fork/repository.
- `.github/workflows/build-and-publish.yml` builds the daily packages and
  publishes them (GitHub prerelease, APT repository on GitHub Pages).
  Deliberately repository-agnostic: it takes the commit to build as an
  input, carries no hardcoded repository-name guard, and can be run
  standalone via `workflow_dispatch` — including, unchanged, from another
  repository such as the upstream `sm0svx/svxlink` project — as well as
  being invoked as a reusable workflow (`workflow_call`) by
  `sync-upstream.yml`.

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
currently maintained Debian-based target versions and architectures, each
in a native `debian:<suite>-slim` container on a runner matching the
target architecture (no QEMU emulation):

| Suite      | Debian version        | Architecture | Runner            | Covers |
|------------|------------------------|--------------|--------------------|--------|
| `bookworm` | Debian 12 (oldstable) | `arm64`      | `ubuntu-24.04-arm` | Raspberry Pi OS Bookworm, Debian 12 (arm64) |
| `trixie`   | Debian 13 (stable)    | `arm64`      | `ubuntu-24.04-arm` | Raspberry Pi OS Trixie, Debian 13 (arm64) |
| `bookworm` | Debian 12 (oldstable) | `amd64`      | `ubuntu-24.04`     | Debian 12 on Intel/AMD (amd64) |
| `trixie`   | Debian 13 (stable)    | `amd64`      | `ubuntu-24.04`     | Debian 13 on Intel/AMD (amd64) |

Debian and Raspberry Pi OS share the same package base per codename (same
library versions, same ABI); one build per suite/architecture therefore
covers both at once (where Raspberry Pi OS supports that architecture),
and a separate "Raspberry Pi OS" variant is not needed. As soon as one of
these Debian versions changes support status (e.g. a new Debian version
becomes stable), the matrix in `.github/workflows/build-and-publish.yml` is
adjusted accordingly — older entries removed, new ones added.

The matrix legs deliberately run sequentially (`max-parallel: 1`), since
the publish step commits to the shared `gh-pages` branch and a parallel
push there would be race-prone. Each leg builds exactly the commit output
by the sync; on the daily schedule this whole job is skipped rather than
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
the respective suite, `.deb` and `SHA256SUMS` are uploaded per leg directly
with the GitHub CLI into its own daily prerelease (tag and title include
suite/architecture, so the legs do not overwrite each other). The tag
points to the built commit. No prerelease is marked as "Latest". There are
no Actions artifacts and no build cache; temporary files are removed after
the upload. A failed leg does not publish a new prerelease. `fail-fast`
is on (the default): a failing leg almost always means the same bug in
the shared script would hit every other leg too, so remaining queued
legs are cancelled immediately and the whole run is marked failed,
rather than burning CI time repeating the same failure four times.
`cleanup-old-releases` and `deploy-pages` still run afterwards
(`if: always()`) regardless, to publish/prune whatever legs did
complete — see "Retention" below.

The `.github/scripts/build-daily-deb.sh` script determines the
architecture (`dpkg --print-architecture`) and distribution codename
(`VERSION_CODENAME` from `/etc/os-release`) from the respective build
container itself instead of hardcoding them. An additional matrix entry
for a further Raspberry Pi OS/Debian/Ubuntu version or architecture
therefore simply calls the same script with a different `--platform`/base
image and a runner matching that architecture (e.g. `ubuntu:24.04` for
Ubuntu Noble, or `arch: armhf` on an arm runner for 32-bit Raspberry Pi
OS); the version scheme, conflicts and the subsequent publishing adapt
automatically.

## APT repository on GitHub Pages

After the daily prerelease, each matrix leg additionally publishes its
package into a shared APT repository, committed to the `gh-pages` branch,
so that all currently maintained versions can be fetched with `apt
install` and updated automatically (see "Installing on Raspberry Pi OS
and Debian" below). The `gh-pages` branch itself is only used as the
persistent, incremental data store the retention/pool logic reads and
writes; it is not what GitHub serves directly. A separate `deploy-pages`
job (`needs: daily-deb`, `if: always()`) runs once per workflow run after
all legs finish, checks out that branch's current content and publishes
it via `actions/configure-pages` + `actions/upload-pages-artifact` +
`actions/deploy-pages` — the `GitHub Actions` Pages source, not the
classic `Deploy from a branch` one. `configure-pages` creates or switches
the repository's Pages site to this source automatically if it is not
already, so no manual Pages setup step is needed. This deliberately
avoids `Deploy from a branch`: that source makes GitHub run its own
internal `pages-build-deployment` workflow outside this repository (not a
file under `.github/workflows/`), which has been observed pinned to a
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
dists/<suite>/main/binary-<arch>/Packages[.gz]
pool/<suite>/main/<letter>/<package-name>/<package>.deb
pubkey.gpg                                   # public signing key
```

`<suite>` is the distribution codename (currently `bookworm` and `trixie`,
see matrix above), `<arch>` the Debian architecture (currently `arm64` and
`amd64`). A later build for e.g. a 32-bit architecture or a new Debian
version simply adds a further `binary-armhf` or `dists/<new suite>/...`
branch; existing suites/architectures remain unchanged. Separate paths are
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
repository's pool follow the same grandfather-father-son retention policy,
implemented once in `.github/scripts/gfs-retention.sh` and applied
independently per series (per suite for releases; per
package/suite/architecture for the pool) so every currently maintained
suite always keeps its own recent history:

| Age                | Kept                          |
|--------------------|--------------------------------|
| < 1 week            | every daily build              |
| 1 week – 1 month    | the newest build per ISO week  |
| 1 month – 1 year    | the newest build per month     |
| ≥ 1 year            | nothing                        |

For the pool, pruning happens as part of `publish-apt-repo.sh` on every
run, right after the new package is added and before the index is
rebuilt. For releases, a separate `cleanup-old-releases` job runs once
per workflow run, after all `daily-deb` matrix legs have finished
(`if: always()`, so it still runs even if a leg failed); it lists all
`daily-*` releases, groups them by suite (the last segment of the tag),
and deletes each release together with its tag
(`gh release delete <tag> --yes --cleanup-tag`) if it falls outside the
window for its suite. The build date is parsed from the
`+daily<YYYYMMDD>` marker in the version string; anything that does not
match this shape is left untouched rather than risk deleting something
unrelated.

## Installing on Raspberry Pi OS and Debian

Once GitHub Pages has been deployed at least once (see "Setup" — no manual
enabling needed), the repository can be added. The commands are identical for all supported
systems; only the codename in the repository line differs:

| Operating system                   | Codename    |
|-------------------------------------|-------------|
| Raspberry Pi OS Trixie (64-bit)    | `trixie`    |
| Raspberry Pi OS Bookworm (64-bit)  | `bookworm`  |
| Debian 13 (Trixie)                  | `trixie`    |
| Debian 12 (Bookworm)                | `bookworm`  |

Both codenames are currently maintained for `arm64` (Raspberry Pi OS,
Debian) and `amd64` (Debian on Intel/AMD PCs and servers); see the matrix
in the "Daily package" section above. A 32-bit Raspberry Pi OS (`armhf`)
is not covered yet.

On the target system, pick up the matching codename automatically and set
up the repository:

```sh
# Import the public signing key
curl -fsSL https://criede.github.io/svxlink-db9cr/pubkey.gpg | \
  sudo gpg --dearmor -o /usr/share/keyrings/svxlink-db9cr.gpg

# Add the repository source, restricted to the key and to the local
# codename/architecture combination
codename=$(sed -n 's/^VERSION_CODENAME=//p' /etc/os-release | tr -d '"')
arch=$(dpkg --print-architecture)
echo "deb [signed-by=/usr/share/keyrings/svxlink-db9cr.gpg arch=${arch}] https://criede.github.io/svxlink-db9cr ${codename} main" | \
  sudo tee /etc/apt/sources.list.d/svxlink-db9cr.list

sudo apt update
sudo apt install svxlink
# Optional graphical EchoLink client (needs a desktop environment):
# sudo apt install qtel
```

If the detected codename is not (yet) part of the matrix, `apt update`
reports a 404 for the affected source; in that case, either set the
codename in `/etc/apt/sources.list.d/svxlink-db9cr.list` manually to one
of the values listed above, or wait for the matrix to be extended.

After that, a regular `sudo apt upgrade` automatically delivers the
latest daily version for the installed system. These are daily development
builds, not stable releases — see the notes above on scope and test
coverage.

## Admin customizations to the TCL event scripts

The TCL files under `/usr/share/svxlink` (`events.tcl`, `events.d/*.tcl`,
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
the package are never touched by dpkg.

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
   above) — without this secret, the `daily-deb` job fails while signing
   the APT repository.
4. Start a first run under **Actions → Sync upstream → Run workflow**
   (or, to build/publish without going through the upstream merge,
   **Actions → Build and publish → Run workflow** directly).

No manual GitHub Pages setup step is needed: the `deploy-pages` job's
`actions/configure-pages` step creates (or switches) the Pages site to
the `GitHub Actions` source itself on the first run.

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
