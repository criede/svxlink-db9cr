# Notes for agents

## Project

svxlink-db9cr is based on SvxLink, a modular voice services system for
amateur radio. The project contains C/C++ source code, Tcl scripts and a
CMake-based build. The goal and scope of the local DB9CR customizations
still need to be documented.

## Orientation

- `README.adoc`: project overview.
- `INSTALL.adoc`: installation and build notes.
- `src/CMakeLists.txt`: entry point of the CMake build.
- `src/svxlink/`: server, modules, scripts and other radio components.
- `src/async/`: libraries for asynchronous processing and audio.
- `src/qtel/`: graphical EchoLink client.
- `src/doc/`: documentation and release notes.
- `TODO.MD`: open tasks.
- `CHANGELOG.MD`: log of local changes.

## Working method

- Check existing code, documentation and git status before making changes.
- Preserve the user's existing changes.
- Keep changes scoped to the task at hand and follow the existing style.
- Do not commit credentials or other sensitive configuration values.
- Verify functional changes with matching builds or targeted tests; check
  `INSTALL.adoc` for the prerequisites.
- State which checks were actually run and any remaining limitations.
- Update the task list and change log for relevant changes.
- Always use a currently maintained Node.js version in workflows,
  preferably a supported LTS release. This also applies to the internal
  Node.js runtime of any actions used: pick suitably maintained action
  versions and check their `runs.using`. `actions/setup-node` alone does
  not change the internal runtime of other actions. Do not use EOL
  versions or workarounds to keep using deprecated runtimes.
- All Markdown (`.md`/`.MD`) documentation files in this repository are
  written in English, regardless of the language used in the request that
  produced them. This does not apply to `src/doc/` and other files
  synchronized from upstream (`sm0svx/svxlink`), which keep their
  upstream language and content.
- The Node.js version rule above also applies to GitHub Pages: do not rely
  on the classic "Deploy from a branch" Pages source, since it makes
  GitHub run its own internal `pages-build-deployment` workflow outside
  this repository's control (and outside `.github/workflows/`), which has
  been observed pinned to a deprecated Node.js runtime with no way for us
  to update it. Deploy via a `GitHub Actions` Pages source instead, using
  our own workflow with pinned, currently-maintained actions
  (`actions/upload-pages-artifact`, `actions/deploy-pages`), so the Node.js
  version is under the same control as every other workflow.
- The gh-pages APT repository's `index.html` must list every published
  package with the features/optional dependencies built into it (e.g.
  RTL-SDR support, SipLogic). Whenever a package's build flags or bundled
  dependencies change, update the `index.html` generation in
  `.github/scripts/publish-apt-repo.sh` (and `BUILD-INFO.MD`/
  `UPSTREAM-SYNC.MD` where relevant) in the same change, not as a
  follow-up — this listing must never fall behind what is actually built.

## Upstream workflows

- Keep actions taken over from upstream disabled in `criede/svxlink-db9cr`.
- Keep the project's own `Sync upstream` workflow enabled.
- During sync, keep `.github/workflows/` fully at its own state; do not
  take over new, changed or deleted workflow files from upstream.

## File name

This file is named `AGENT.MD` as requested. Tools that load instructions
from `AGENTS.md` may not recognize it automatically under this name.
