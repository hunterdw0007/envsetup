# AGENTS.md

Standards for anyone (human or agent) working on this repo. This file is the source of
truth — if a PR or commit doesn't follow it, that's a bug in the PR, not in this file.

## Commit messages

Conventional Commits, always: `<type>(<scope>)?: <summary>`.

- Common types here: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `ci`.
- Scope is usually the directory or concept the change lives in: `home`, `work`,
  `packages`, `installers`. Omit it for changes that don't fit one area (e.g. a root
  `README.md`-only change).
- A breaking change (e.g. the workflow/menu structure changes such that a prior habit
  no longer works) uses `!` after the type/scope: `feat!: ...`.
- Body explains *why*, not a restatement of the diff. Reference the PR/issue that
  motivated the change if there is one.

## Branching and PRs

- Never push directly to `main`. Every change goes through a feature branch and a PR.
- If a change depends on another open, unmerged PR, base the new branch on that PR's
  branch (not `main`) so the diff shown is just the incremental change, and say so in
  the PR description ("stacked on #N").
- Don't open a PR unless asked to. Creating the branch/commit is not the same as
  opening the PR — confirm which is wanted when it's ambiguous.
- PR descriptions include a "Test plan" section stating what was actually verified
  (see Testing below), not just what the change does.

## Shell script standards

- Shebang `#!/usr/bin/env bash`, and `set -euo pipefail` at the top of every
  executable script (`setup.sh`, `install.sh`, everything under `installers/`).
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
  system, add a row to `packages/names.txt`.
- Anything else — a vendor installer script, a manual binary download, an arbitrary
  custom setup step → `installers/common/` or `installers/<profile>/`.
- A shared, non-identity git setting or alias → `git/gitconfig` (merged with the user's
  `ENVSETUP_GIT_CONFIG` into `~/.config/envsetup/gitconfig` by `lib/git.sh`). Identity
  (`user.name`/`user.email`) is prompted for at runtime or set in the user's own
  `config.sh` — never committed to this repo.
- Anything specific to one *user* rather than to the repo's defaults never goes in a
  tracked file: it belongs in their `~/.config/envsetup/config.sh` (template:
  `config.example.sh`). Editing tracked files to customize is exactly what makes
  `git pull` / `install.sh` fail for someone who didn't fork.
- The `ENVSETUP_*` variables read from `config.sh` are a user-facing API. A new
  overridable setting gets its default in `envsetup::load_config` (`lib/config.sh`) and
  is documented in both `config.example.sh` and the README's settings table. Renaming
  one or changing its meaning breaks existing users' configs, so it's a `!` change.
- `work`'s `lite` mode skips both `packages/work.txt` and `installers/work/` entirely
  (no sudo assumed) — don't add something to either that `lite` actually needs; it
  belongs in `shell/shared/` or `shell/profiles/work/` instead. `lib/git.sh` is not
  gated by `lite`: it only ever writes to `$HOME/.gitconfig`, no sudo required.

## Testing

CI (`.github/workflows/ci.yml`) runs two jobs on every push and PR:

- `shell-checks`: `bash -n` and `shellcheck` over every `*.sh` file.
- `smoke`: `tests/smoke.sh` in a bare `ubuntu:24.04` container — `install.sh` on a box
  with no git, then every profile's "Run everything", then a real bash and zsh loading
  the result. Only gum's UI, package installs and vendor downloads are stubbed, so it
  takes about 20s. Run it locally the same way CI does:
  `docker run --rm -t -v "$PWD:/src:ro" ubuntu:24.04 bash /src/tests/smoke.sh`.
  A new menu action, profile or mode needs a scenario there, and every check must be
  able to fail: compare against a non-empty expected value, never two things that
  could both come back empty.

`tests/distros/run.sh` (manual, not CI; see the README) runs the real tool against a
dozen distros with real installs. Run it after changing anything distro-specific: package
lists, `envsetup::pkg_install`/`pkg_manager`, installers, `install.sh`.

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
