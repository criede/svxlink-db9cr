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
- `.github/workflows/sync-upstream.yml`: merges upstream, then calls
  `build-and-publish.yml`.
- `.github/workflows/build-and-publish.yml`: builds/tests/publishes the
  daily packages and APT repository; repository-agnostic, reusable.
- `.github/workflows/build-releases.yml`: builds/publishes packages of the
  upstream release tags (26.05+) into the APT component `release`.
- `.github/workflows/build-deb.yml`: reusable per-target build/test job
  used by both; targets are listed in `.github/build-targets.json`.
- `.github/scripts/`: the shell scripts those workflows run.
- `.github/pages/`: APT repository start page templates (English master,
  translations in `i18n/`, language list `languages.tsv`).

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
  dependencies change, update the start page template
  `.github/pages/index.html.in` (its package table) and all its
  translations (see the next rule), plus `BUILD-INFO.MD`/
  `UPSTREAM-SYNC.MD` where relevant, in the same change, not as a
  follow-up — this listing must never fall behind what is actually built.
- The start page exists in English (`.github/pages/index.html.in`, the
  master) and in translations into the European languages listed in
  `.github/pages/languages.tsv` (`.github/pages/i18n/index.<lang>.html.in`,
  rendered to `index.<lang>.html` by `.github/scripts/render-start-page.sh`). Whenever the
  English template changes, update **every** translation in the same
  change, never as a follow-up: translate the changed text, keep the HTML
  structure and `@@...@@` placeholders identical, and set each
  translation's `<meta name="source-sha256" content="...">` to the hash
  printed by `bash .github/scripts/check-translations.sh` (which must
  then report every language as `current`; the `Check start page
  translations` workflow fails otherwise). Every translated page carries
  a notice that it is an AI-generated translation, with a link to the
  English original; the generator inserts it from the notice column of
  `languages.tsv`, so a new language needs its notice text there too.
  Do not put that notice into the templates themselves.
- Before adding an `apt-get install` package name in a workflow/build
  script, verify it actually exists for the target suite (and provides
  what is needed, e.g. a specific `.cmake` file) rather than guessing from
  naming convention or memory — Debian's Qt6 packaging in particular does
  not follow the "obvious" name (e.g. `Qt6LinguistTools`'s CMake config is
  in `qt6-tools-dev`, not `qt6-l10n-tools`; `Qt6Core5Compat`'s is in
  `qt6-5compat-dev`, not `libqt6core5compat6-dev`). A wrong guess here
  only surfaces after a multi-minute CI build, so check first via
  `https://packages.debian.org/search?searchon=contents&keywords=<file>&mode=exactfilename&suite=<suite>`
  for the file it needs to provide.

## Upstream workflows

- Keep actions taken over from upstream disabled in `criede/svxlink-db9cr`.
- Keep the project's own `Sync upstream` workflow enabled.
- During sync, keep `.github/workflows/` fully at its own state; do not
  take over new, changed or deleted workflow files from upstream.

## File name

This file is named `AGENT.MD` as requested. Tools that load instructions
from `AGENTS.md` may not recognize it automatically under this name.
