# AGENTS.md

Standards for anyone (human or agent) working on this repo. This file is the source of
truth — if a PR or commit doesn't follow it, that's a bug in the PR, not in this file.

## Commit messages

Conventional Commits, always: `<type>(<scope>)?: <summary>`. They aren't just style:
releases are versioned and described from them (see Releases below), and CI
(`.github/workflows/commits.yml`) checks every commit in a PR, and the PR title, with
commitizen. `cz check --rev-range origin/main..HEAD` runs the same check locally, and
`cz commit` writes a message interactively (`pipx install commitizen`).

- Common types here: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `ci`.
- Scope is usually the directory or concept the change lives in: `home`, `work`,
  `packages`, `installers`. Omit it for changes that don't fit one area (e.g. a root
  `README.md`-only change).
- A breaking change (e.g. the workflow/menu structure changes such that a prior habit
  no longer works) uses `!` after the type/scope: `feat!: ...`. It bumps the major
  version (the minor one while on 0.x; see Releases) and is listed under "Breaking
  changes" in the release notes.
- PRs are squash-merged, so the PR title becomes the commit on `main` that the release
  is worked out from: it follows the same format, with the type and `!` of the most
  significant change in the PR.
- Body explains *why*, not a restatement of the diff. Reference the PR/issue that
  motivated the change if there is one.

## Branching and PRs

- Never push directly to `main`. Every change goes through a feature branch and a PR.
  The one exception is the release job's bump commit (see Releases).
- If a change depends on another open, unmerged PR, base the new branch on that PR's
  branch (not `main`) so the diff shown is just the incremental change, and say so in
  the PR description ("stacked on #N").
- Don't open a PR unless asked to. Creating the branch/commit is not the same as
  opening the PR — confirm which is wanted when it's ambiguous.
- PR descriptions include a "Test plan" section stating what was actually verified
  (see Testing below), not just what the change does.

## Releases

Every push to `main` whose commits call for a new version is released automatically,
once CI passes (the `release` job in `.github/workflows/ci.yml`, which runs
`.github/scripts/release.sh`). commitizen (`.cz.toml`) reads the commits since the last
release:

| Commits since the last release | Next version, while on 0.x | From 1.0.0 on |
| --- | --- | --- |
| any with `!` (or a `BREAKING CHANGE:` footer) | minor: `v0.4.2` → `v0.5.0` | major: `v1.4.2` → `v2.0.0` |
| `feat` | minor: `v0.4.2` → `v0.5.0` | minor: `v1.4.2` → `v1.5.0` |
| `fix`, `refactor`, `perf` | patch: `v0.4.2` → `v0.4.3` | patch: `v1.4.2` → `v1.4.3` |
| only `docs`, `ci`, `test`, `chore`, `style`, `build` | no release | no release |

A release is a `bump: version X → Y` commit by `github-actions[bot]` on `main` that adds
the version's entry to `CHANGELOG.md`, an annotated `vX.Y.Z` tag on that commit, and a
GitHub release with the same entry as its notes. The current version is the newest tag
(`version_provider = "scm"`). `install.sh` checks out the newest release unless
`ENVSETUP_VERSION` names another, so a release is what users run.

- `CHANGELOG.md` is written only by the release job: editing it in a PR conflicts with
  the next bump commit. Fix a wrong entry with a follow-up release, not by hand.
- Never create, move or delete a `v*` tag or a release by hand. People pin to versions,
  and a tag that moves changes what they install. A bad release is fixed by the next
  one (`fix: ...`), not by retagging.
- Don't run `cz bump` yourself (it commits and tags locally, and only CI pushes those).
  To see what merging would release, run `cz bump --get-next` on an up-to-date `main`
  with the PR's commits on top.
- Leaving 0.x is a deliberate PR: set `major_version_zero = false` in `.cz.toml`, as a
  breaking change (`chore!: ...`), and its release is `v1.0.0`.
- If the `release` job fails, re-run it: when the commit is already released, it only
  creates the missing GitHub release. If `main` moved on while it ran, it pushes nothing
  and warns; the next commit on `main` to pass CI releases both.
- commitizen and all its dependencies are hash-locked in
  `.github/actions/commitizen/requirements.txt` (change the version in `requirements.in`
  and re-run the command at the top of the `.txt`). That lock is what keeps third-party
  code out of the job that can push to `main`; don't loosen it. The job also runs
  `release.sh bump` (commitizen, no token in the checkout) and then `release.sh publish`
  (the push and the GitHub release; never runs commitizen), which keeps the token out of
  commitizen's process, but steps of one job share the runner (`$GITHUB_PATH`,
  `$GITHUB_ENV`, the workspace), so that split is defense in depth, not a boundary.
- `tests/release.sh` runs the release job's two steps against a scratch origin (first
  release, re-runs, no-op, race, refused push). CI runs it on every push and PR, and the
  release job waits for it; extend it with any change to the release flow.
- The job pushes with `GITHUB_TOKEN`, which works while `main` has no branch protection.
  If `main` gets protection or a ruleset, add a `RELEASE_TOKEN` secret (a fine-grained
  token or GitHub App token allowed to bypass it, with contents: write).

## Shell script standards

- Shebang `#!/usr/bin/env bash`, and `set -euo pipefail` at the top of every
  executable script (`setup.sh`, `install.sh`, everything under `installers/`). Test
  harnesses under `tests/` may leave out `-e`, so one failed check doesn't stop the rest.
- `install.sh`, and `setup.sh` up to where it re-runs itself under a newer bash, run under
  macOS's bash 3.2: no `readarray`/`mapfile`, associative arrays, `${x,,}`, or bare
  `"${arr[@]}"` of a possibly empty array under `set -u` (use `${arr[@]+"${arr[@]}"}`).
  The `lib/` and `shell/` files may use bash 4+ inside functions, but must still parse
  under 3.2. CI's bash 3.2 step checks the parsing, `setup.sh --help` and its "needs bash 4" exit.
- Indent with tabs, matching the rest of the repo.
- Use `[[ ]]` over `[ ]`, quote variable expansions, prefer bash builtins
  (`readarray`, `[[ =~ ]]`, parameter expansion) over spawning external tools where
  a builtin does the job.
- Namespace functions as `envsetup::<name>` (see `lib/common.sh`, `lib/zsh.sh`,
  `lib/installers.sh`) — this is a flat function namespace, not real modules, so the
  prefix is what keeps names from colliding. Variables shared across files use
  `ENVSETUP_*`; temporaries in a sourced file (e.g. `shell/init.sh`, which runs inside
  the user's interactive shell) use a `_envsetup_` prefix and are `unset` afterwards.
- Anything a user picks from should say what it does. Build that text from the resolved
  config (`envsetup::resolved_packages` / `envsetup::resolved_installers` in
  `lib/config.sh`, the same functions the actions run on), never a hand-written count
  that can drift. Picker lines are `"<value>  <description>"` and the caller keeps
  `${choice%% *}`: `gum choose --label-delimiter` would do the same, but only on newer
  gum releases, and an older one would reject the flag and silently break the picker.
- Every step that changes the machine (writes a file, installs, runs sudo/chsh, calls
  out to the network) checks `envsetup::dry_run` *before its first write* and describes
  the change with `envsetup::would` instead. The smoke test's dry-run scenarios snapshot
  `$HOME` and fail on any write, so a missed guard doesn't go unnoticed.
- Anything new that envsetup writes outside this repo (a file, an rc-file line, a git
  setting) is also removed by `envsetup::uninstall` (`lib/uninstall.sh`), with a check in
  the smoke test's uninstall scenarios. Uninstall removes only what envsetup itself
  created; anything the user may own (their `config.sh`, their login shell) is asked
  about, phrased as "Keep …?" so the default answer is the safe one.
- Options are parsed before `envsetup::ensure_gum`, so anything that doesn't need the TUI
  (`--help`, rejecting an unknown option) works on a machine that doesn't have gum yet.
- Under `set -e`, a function whose last command is `[[ ... ]] && x` returns non-zero
  when the test is false, and `var=$(that_function)` then kills the script. End such
  functions with `if ...; then ...; fi` instead.
- Never run a step as `step || handle_failure`: bash switches `set -e` off inside
  everything `step` calls, so a failure halfway through carries on silently. Menu
  actions go through `envsetup::run_step` (`setup.sh`), which runs them in a subshell
  with `set -e` intact and returns to the menu if they fail.
- Every shell script must pass `bash -n <file>` and `shellcheck <file>` before it's
  committed — CI (`.github/workflows/ci.yml`) enforces both on every push/PR, so a
  script that doesn't pass locally will fail there too. Prefer an inline
  `# shellcheck disable=SC____` with a comment explaining why over silencing a whole
  file, and prefer fixing the actual issue over disabling it when the fix is simple
  (e.g. `VAR=$(cmd); export VAR` instead of `export VAR=$(cmd)`, per SC2155).
  A file that's only ever `source`d (never executed directly), like the ones under
  `shell/shared/` and `shell/profiles/`, needs `# shellcheck shell=bash` as its first
  line so shellcheck knows the dialect (see SC2148).
- No inline `#` comments on a `packages/*.txt` package-name line — the line is passed
  verbatim to the package manager, so a comment on the same line breaks the install.
  Put the comment on the line above instead.

## Installer scripts (`installers/<profile-or-common>/*.sh`)

- Must be idempotent: check whether the tool is already present and `exit 0`
  immediately if so, before touching the network. `installers/work/kubectl.sh` is the
  reference example.
- Runs as its own `bash` process (not sourced), so `source "$ENVSETUP_ROOT/lib/common.sh"`
  explicitly if you need its helpers.
- One script failing must not stop the others — `lib/installers.sh` already handles
  this; don't add a `set -e`-defeating workaround inside an individual script to try
  to do the same thing.
- On macOS, hand over to Homebrew right after the already-installed check:
  `[[ "$OSTYPE" == darwin* ]] && exec brew install <formula>`, which ends the script there
  (the downloads that follow are Linux builds).
- Download the build for the machine (`envsetup::arch` gives `amd64`/`arm64`), run root
  steps through `envsetup::as_root` (sudo, doas, or already root), and document any
  remaining OS/arch assumption in a comment.

## Where new content goes

- A shell alias/export/function everyone should get → `shell/shared/`.
- One that only applies to one profile → `shell/profiles/<profile>/`.
- Everything under `shell/` is sourced by both bash and zsh (opt-in on any profile). Code
  that's bash-only (arrays, `mapfile`, bash prompt escapes) goes in a file that starts
  with `[[ -n "${BASH_VERSION:-}" ]] || return 0`, like `shell/shared/ps1.sh`. An alias
  or export that relies on an optional tool is defined only when that tool is installed
  (`bat` in `shell/shared/aliases.sh`). Work lite installs nothing, and a `cat` alias
  pointing at a missing binary breaks `cat` itself.
- A tool installable by name from the distros' package managers → `packages/common.txt`
  or `packages/<profile>.txt`, by its Debian/Ubuntu name. If another manager (`dnf`,
  `zypper`, `pacman`, `apk`, `brew`, `nix`) calls it something else, or has it in the base
  system, add a row to `packages/names.txt` (its `macos` column is for where Homebrew on
  macOS differs from Homebrew on Linux).
- Anything else — a vendor installer script, a manual binary download, an arbitrary
  custom setup step → `installers/common/` or `installers/<profile>/`. A popular tool
  that only some users want and that major distros (Ubuntu LTS, Fedora) don't package →
  `installers/extras/`, opted into by name with `ENVSETUP_EXTRAS`; download with
  `envsetup::release_sha256` + `envsetup::install_release` so the checksum is verified.
- A tool that needs a shell hook to work (direnv, zoxide) → `shell/shared/tools.sh`,
  guarded on the tool being installed.
- A shared, non-identity git setting or alias → `git/gitconfig` (merged with the user's
  `ENVSETUP_GIT_CONFIG` into `~/.config/envsetup/gitconfig` by `lib/git.sh`). Identity
  (`user.name`/`user.email`) is prompted for at runtime or set in the user's own
  `config.sh` — never committed to this repo.
- Anything specific to one *user* rather than to the repo's defaults never goes in a
  tracked file: it belongs in their `~/.config/envsetup/config.sh` (template:
  `config.example.sh`). Editing tracked files to customize is exactly what makes
  updating (re-running `install.sh`) fail for someone who didn't fork.
- The `ENVSETUP_*` variables read from `config.sh` are a user-facing API. A new
  overridable setting gets its default in `envsetup::load_config` (`lib/config.sh`) and
  is documented in both `config.example.sh` and the README's settings table. Renaming
  one or changing its meaning breaks existing users' configs, so it's a `!` change.
- `work`'s `lite` mode skips both `packages/work.txt` and `installers/work/` entirely
  (no sudo assumed) — don't add something to either that `lite` actually needs; it
  belongs in `shell/shared/` or `shell/profiles/work/` instead. `lib/git.sh` is not
  gated by `lite`: it only ever writes to `$HOME/.gitconfig`, no sudo required.

## Testing

CI (`.github/workflows/ci.yml`) runs three jobs on every push and PR, plus `release` (see
Releases) on pushes to `main` once they pass; `.github/workflows/commits.yml` checks
commit messages and the PR title on every PR:

- `shell-checks`: `bash -n` and `shellcheck` over every `*.sh` file.
- `smoke`: `tests/smoke.sh` in a bare `ubuntu:24.04` container — `install.sh` on a box
  with no git, picking and switching releases, then every profile's "Run everything",
  then a real bash and zsh loading the result. Only gum's UI, package installs and vendor
  downloads are stubbed, so it takes about 20s. CI runs it offline, from cached copies of
  the few packages it installs with real apt (Ubuntu's archive is often slow from CI); run
  it locally with `docker run --rm -t -v "$PWD:/src:ro" ubuntu:24.04 bash /src/tests/smoke.sh`.
  A new menu action, profile or mode needs a scenario there, and every check must be
  able to fail: compare against a non-empty expected value, never two things that
  could both come back empty.
- `release-script`: `tests/release.sh`, the release flow against a scratch origin, with
  the hash-locked commitizen. Run it locally with `cz` on PATH.

`tests/distros/run.sh` (manual, not CI; see the README) runs the real tool against a
dozen distros with real installs. Run it after changing anything distro-specific: package
lists, `envsetup::pkg_install`/`pkg_manager`, installers, `install.sh`.
`tests/macos.sh` is the same for macOS, on GitHub's macOS runners (the `macos` workflow,
opt-in by label or dispatch, since their minutes cost 10x) or on a Mac. Run it after changing anything a Mac
takes a different path through (`brew`, bash 3.2 code, BSD tools).

The smoke test proves the flows run; it doesn't prove every branch. Behavior is still
verified and described in the PR:

- `bash -n` and `shellcheck` every changed/added script (CI re-checks this, but catch
  it before pushing).
- Exercise the actual functions (`source`'d, not just read) against mocked external
  commands (`curl`, `sudo`, `gum`, `git`, package managers) in an isolated `$HOME` —
  don't hit real networks, install real system packages, or change real shell/system
  state as part of verifying a PR. Cover both the "already installed / already linked"
  no-op path and the "needs to run" path for anything idempotent.
- For anything touching `setup.sh` or the menu, also run `tests/smoke.sh` locally
  (command above), which drives the real `./setup.sh` end to end from fresh `$HOME`s.
  Function-level tests alone missed that `setup.sh` exited before the menu on every
  first run.
- Never make PR- or commit-related state changes (or GitHub API calls) as a *side
  effect* of testing — testing is local and disposable.
