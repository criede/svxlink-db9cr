# Daily upstream synchronization

The `Sync upstream` workflow merges all new commits from `sm0svx/svxlink`,
branch `master`, into `criede/svxlink-db9cr`, branch `master`, daily at
02:17 UTC. That corresponds to 03:17 in winter and 04:17 in summer, German
time. Other branches, tags and GitHub releases are not synchronized.

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
becomes stable), the matrix in `.github/workflows/sync-upstream.yml` is
adjusted accordingly — older entries removed, new ones added.

The matrix legs deliberately run sequentially (`max-parallel: 1`), since
the publish step commits to the shared `gh-pages` branch and a parallel
push there would be race-prone. Each leg builds exactly the commit output
by the sync, even if there were no new upstream commits. The server build
does not include Qtel or sound files; these must be installed to match the
station.

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
the upload. A failed leg does not publish a new prerelease and, thanks to
`fail-fast: false`, does not block the other legs.

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
package into a shared APT repository on the `gh-pages` branch, so that all
currently maintained versions can be fetched with `apt install` and
updated automatically (see "Installing on Raspberry Pi OS and Debian"
below).

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
So that the `gh-pages` branch does not grow without bound, only the last
14 daily versions are kept per package/suite/architecture (`RETENTION`
parameter in the script); older `.deb` files are removed before rebuilding
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

## Installing on Raspberry Pi OS and Debian

Once GitHub Pages is enabled for the `gh-pages` branch (see "Setup"), the
repository can be added. The commands are identical for all supported
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
codename=$(. /etc/os-release && echo "$VERSION_CODENAME")
arch=$(dpkg --print-architecture)
echo "deb [signed-by=/usr/share/keyrings/svxlink-db9cr.gpg arch=${arch}] https://criede.github.io/svxlink-db9cr ${codename} main" | \
  sudo tee /etc/apt/sources.list.d/svxlink-db9cr.list

sudo apt update
sudo apt install svxlink
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

## Setup

1. Push the workflow to the GitHub repository's default branch.
2. Enable GitHub Actions in the repository, if not already done.
3. Create the repository secret **APT_SIGNING_KEY** (see "Signing key"
   above) — without this secret, the `daily-deb` job fails while signing
   the APT repository.
4. Under **Settings → Pages**, set the source to **Deploy from a branch**
   and the branch to `gh-pages` (directory `/`). The branch is created
   automatically on the first successful `daily-deb` run; this setting can
   therefore also be made after that run.
5. Start a first run under **Actions → Sync upstream → Run workflow**.

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

## Sources

- [GitHub: Events that trigger workflows](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows)
- [GitHub: GITHUB_TOKEN](https://docs.github.com/en/actions/concepts/security/github_token)
- [GitHub: Permissions for workflow changes](https://github.github.com/gh-aw/reference/safe-outputs-pull-requests/)
- [GitHub Pages: Deploy from a branch](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site)
- [Debian Wiki: SecureApt](https://wiki.debian.org/SecureApt)
- [Debian Repository Format](https://wiki.debian.org/DebianRepository/Format)
- [Debian Policy Manual: conffiles](https://www.debian.org/doc/debian-policy/ch-files.html#configuration-files)
