# AGENTS.md

This file sets the standards for this repo. They apply to people and to agents.
If a PR or commit breaks a rule here, fix the PR, not this file.

## Requirements and goals

[`CONTRIBUTING.md`](CONTRIBUTING.md#requirements) lists the requirements and goals of envsetup.
Every change must keep the requirements true.

## Writing rules

All writing in this repo follows these five rules.
They cover docs, code comments, messages that users see, commit messages and PR descriptions.

1. Use active voice.
2. Write all sentences in 20 words or fewer.
3. Include only one idea per sentence.
4. Use the same word for the same thing every time.
5. Do not use idioms or jargon.

Names of tools, commands, files and variables are not jargon.
Explain any other technical term the first time you use it.

## Commit messages

Every commit message uses Conventional Commits: `<type>(<scope>)?: <summary>`.
The release job reads these messages to pick the next version and write the release notes (see Releases).
CI checks every commit in a PR with commitizen (`.github/workflows/commits.yml`).
CI also checks the PR title.
`cz check --rev-range origin/main..HEAD` runs the same check locally.
`cz commit` helps you write a message step by step (`pipx install commitizen`).

- The common types are `feat`, `fix`, `chore`, `docs`, `refactor`, `test` and `ci`.
- The scope is usually the directory or area of the change: `home`, `work`, `packages` or `installers`.
  Leave out the scope when a change does not fit one area.
  A change to the root `README.md` alone is an example.
- A breaking change puts `!` after the type or scope: `feat!: ...`.
  A change is breaking when it changes envsetup's API in a way that is not backwards compatible.
  [`CONTRIBUTING.md`](CONTRIBUTING.md#breaking-changes) defines the API and gives examples.
  [`docs/interface.md`](docs/interface.md) lists each part of the API.
  A breaking change raises the major version.
  While the version is 0.x, it raises the minor version instead (see Releases).
  The release notes list it under "Breaking changes".
- GitHub squash-merges PRs, so the PR title becomes the commit on `main`.
  The release job picks the version from that commit.
  So the PR title uses the same format.
  It takes the type and `!` of the most important change in the PR.
- The body explains *why* you made the change.
  Do not repeat the diff in words.
  Link the PR or issue behind the change, if there is one.

## Branches and PRs

- Never push directly to `main`.
  Every change goes through a feature branch and a PR.
  The release job's bump commit is the only exception (see Releases).
- A change may depend on another open PR.
  In that case, base the new branch on that PR's branch, not on `main`.
  The diff then shows only the new change.
  Say so in the PR description: "stacked on #N".
- Do not open a PR unless someone asks for one.
  A branch or a commit is not a request for a PR.
  When the request is unclear, ask which one the person wants.
- Every PR description has a "Test plan" section.
  The test plan states what you checked (see Testing).
  It does not just describe the change.

## Releases

The `release` job in `.github/workflows/ci.yml` releases each push to `main` that needs a new version.
It runs after CI passes, and it runs `.github/scripts/release.sh`.
commitizen (`.cz.toml`) reads the commits since the last release:

| Commits since the last release | Next version, while on 0.x | From 1.0.0 on |
| --- | --- | --- |
| any with `!` (or a `BREAKING CHANGE:` footer) | minor: `v0.4.2` → `v0.5.0` | major: `v1.4.2` → `v2.0.0` |
| `feat` | minor: `v0.4.2` → `v0.5.0` | minor: `v1.4.2` → `v1.5.0` |
| `fix`, `refactor`, `perf` | patch: `v0.4.2` → `v0.4.3` | patch: `v1.4.2` → `v1.4.3` |
| only `docs`, `ci`, `test`, `chore`, `style`, `build` | no release | no release |

A release has three parts:

- `github-actions[bot]` adds a `bump: version X → Y` commit to `main`.
  This commit adds the version's entry to `CHANGELOG.md`.
- An annotated `vX.Y.Z` tag marks that commit.
- A GitHub release uses the same entry as its notes.

The newest tag sets the current version (`version_provider = "scm"`).
`install.sh` downloads the newest release, unless `ENVSETUP_VERSION` names another one.
So users run a release, not `main`.
`install.sh` runs `setup.sh` from a temporary folder and deletes the folder when it ends.
"Link shell config" copies `shell/` to `$XDG_DATA_HOME/envsetup`.
New shells load that copy.
The file `version` next to the copy records the release.

- Only the release job writes `CHANGELOG.md`.
  An edit to it in a PR conflicts with the next bump commit.
  A later release fixes a wrong entry.
  Do not fix an entry by hand.
- Never create, move or delete a `v*` tag or a release by hand.
  People pin to versions.
  A moved tag changes what they install.
  The next release fixes a bad release (`fix: ...`).
  Do not tag a commit again.
- Do not run `cz bump` yourself.
  It commits and tags locally, and only CI pushes those.
  You can still see what a merge would release.
  Put the PR's commits on top of an up-to-date `main`.
  Then run `cz bump --get-next`.
- Leaving 0.x takes its own PR.
  That PR sets `major_version_zero = false` in `.cz.toml`.
  It is a breaking change (`chore!: ...`), and its release is `v1.0.0`.
- If the `release` job fails, run it again.
  If the commit already has a release, the job only creates the missing GitHub release.
  `main` may get a new commit while the job runs.
  In that case the job pushes nothing and prints a warning.
  The next commit on `main` that passes CI then releases both commits.
- `.github/actions/commitizen/requirements.txt` locks commitizen and all its dependencies by hash.
  To change the version, edit `requirements.in`.
  Then run the command at the top of the `.txt` file again.
  The lock keeps other people's code out of the job that can push to `main`.
  Do not loosen the lock.
- The job runs `release.sh bump` first.
  That step runs commitizen without a token in the checkout.
  The job then runs `release.sh publish`.
  That step pushes and creates the GitHub release, and it never runs commitizen.
  This split keeps the token away from commitizen.
  But all steps of one job share the runner, including `$GITHUB_PATH`, `$GITHUB_ENV` and the workspace.
  So the split adds a layer of protection, but it does not isolate the steps.
- `tests/release.sh` runs the release job's two steps against a local test remote.
  It covers a first release, a second run, a run with nothing to release, a race and a refused push.
  CI runs it on every push and PR, and the release job waits for it.
  Add to it whenever you change the release flow.
- The job pushes with `GITHUB_TOKEN`.
  That works while `main` has no branch protection.
  If `main` gets protection or a ruleset, add a `RELEASE_TOKEN` secret.
  Use a fine-grained token or a GitHub App token that can bypass the protection.
  It needs contents: write.

## Shell script standards

- Every executable script starts with the shebang `#!/usr/bin/env bash` and `set -euo pipefail`.
  Executable scripts are `setup.sh`, `install.sh` and everything under `installers/`.
  Test scripts under `tests/` may leave out `-e`.
  Then one failed check does not stop the rest.
- Indent with tabs, like the rest of the repo.
- Use `[[ ]]` instead of `[ ]`.
- Quote variable expansions.
- Use a bash builtin when one does the job, instead of an external tool.
  Examples are `readarray`, `[[ =~ ]]` and parameter expansion.
- Name functions `envsetup::<name>` (see `lib/common.sh`, `lib/zsh.sh` and `lib/installers.sh`).
  Bash has one flat set of function names and no real modules.
  So the prefix keeps names from clashing.
- Variables that several files share use the prefix `ENVSETUP_`.
- A sourced file runs inside the user's own shell.
  `shell/init.sh` is an example.
  Its temporary variables use the prefix `_envsetup_`, and the file `unset`s them at the end.
- Each item in a picker says what it does.
  Build that text from the resolved config.
  Use `envsetup::resolved_packages` or `envsetup::resolved_installers` in `lib/config.sh`.
  The actions run on the same functions.
  Never write a count by hand, because it can get out of date.
- Picker lines are `"<value>  <description>"`, and the caller keeps `${choice%% *}`.
  `gum choose --label-delimiter` does the same, but only newer gum releases have it.
  An older gum rejects the flag, and the picker breaks without an error.
- A step changes the machine when it writes a file, installs, runs sudo or chsh, or uses the network.
  Every such step checks `envsetup::dry_run` *before its first write*.
  In a dry run, it describes the change with `envsetup::would` instead.
  The smoke test's dry-run scenarios take a snapshot of `$HOME` and fail on any write.
  So the smoke test catches a missing check.
- envsetup may write something new outside this repo, such as a file, an rc-file line or a git setting.
  `envsetup::uninstall` (`lib/uninstall.sh`) must also remove it.
  The smoke test's uninstall scenarios must check the removal.
- Uninstall removes only what envsetup created.
  It asks about anything the user may own, such as their `config.sh` or their login shell.
  The question reads "Keep …?", so the default answer is the safe one.
- `setup.sh` parses options before `envsetup::ensure_gum`.
  So options that need no menu work on a machine without gum.
  `--help` and the error for an unknown option are examples.
- Under `set -e`, a function may end with `[[ ... ]] && x`.
  When the test is false, the function returns non-zero.
  Then `var=$(that_function)` stops the script.
  End such functions with `if ...; then ...; fi` instead.
- Never run a step as `step || handle_failure`.
  Bash turns off `set -e` inside everything that `step` calls.
  A failure halfway through then goes unnoticed, and the step keeps running.
  Menu actions go through `envsetup::run_step` (`setup.sh`).
  It runs each action in a subshell with `set -e` still on.
  It returns to the menu if the action fails.
- Every shell script must pass `bash -n <file>` and `shellcheck <file>` before you commit it.
  CI (`.github/workflows/ci.yml`) runs shellcheck on every push and PR.
  shellcheck also fails on syntax errors.
  So a script that fails locally also fails in CI.
- To silence one shellcheck warning, add `# shellcheck disable=SC____` on that line.
  Add a comment that explains why.
  Do not silence a whole file.
  Fix the cause instead when the fix is simple.
  For example, SC2155 asks for `VAR=$(cmd); export VAR` instead of `export VAR=$(cmd)`.
- Some files are only ever `source`d and never run directly.
  The files under `shell/shared/` and `shell/profiles/` are examples.
  Their first line is `# shellcheck shell=bash`, so shellcheck knows the shell (see SC2148).
- `shfmt -i 0` sets the format: tabs, and shfmt's defaults for everything else.
  CI runs `shfmt -d -i 0 .` and fails on any diff.
  `shfmt -w -i 0 .` fixes the format locally.
- CI pins shellcheck v0.11.0 and shfmt v3.14.1 (see the install step in `ci.yml`).
  Use the same versions locally, because a newer version can disagree.
- Do not put a `#` comment at the end of a package name line in `packages/*.txt`.
  envsetup passes the whole line to the package manager.
  A comment on the same line breaks the install.
  Put the comment on the line above instead.

## Installer scripts (`installers/<profile-or-common>/*.sh`)

- An installer must be safe to run more than once.
  It first checks whether the tool is already installed.
  If the tool is installed, it runs `exit 0` before it uses the network.
  `installers/work/kubectl.sh` shows how.
- A pinned installer checks with `envsetup::up_to_date <name> <command>`, not `envsetup::has_cmd`.
  Then it updates a tool that envsetup installed at an older pin.
  It still skips a tool that the user installed.
- After a pinned installer installs its tool, it runs `envsetup::record_installed <name>`.
  That function writes `<name> <version>` to `$XDG_STATE_HOME/envsetup/installed` (by default `~/.local/state/envsetup/installed`).
  `<name>` is the installer's name and its name in `versions.txt`.
  **Run installers** lists an update when this record differs from the pin.
  Uninstall deletes the record and keeps the tools.
- Each installer runs in its own `bash` process and is not sourced.
  To use the helpers in `lib/common.sh`, run `source "$ENVSETUP_ROOT/lib/common.sh"` in the script.
- One failed installer must not stop the others.
  `lib/installers.sh` already handles this.
  Do not add a workaround inside an installer that turns off `set -e`.
- Every download that envsetup installs or runs has a pinned version.
  envsetup checks each download before it uses the file.
  A failed check stops the script.
- Never look up the latest version at install time.
  `installers/versions.txt` holds the version and the sha256 for each platform.
  Read them with `envsetup::pin`.
  Download through `envsetup::install_release`.
- A new tool gets a `pin_<name>` function in `.github/scripts/bump-versions.sh`.
  That function finds the newest release and reads its published checksums.
  Run that script to write the tool's line in `versions.txt`.
- Some projects publish only a signature, not a checksum (awscli).
  For those, pin only the version.
  Check the signature with `envsetup::gpg_verify` against the vendor's key.
  Keep the key next to the script, and pin its fingerprint in the script.
- A tool version bump is a PR.
  The `bump-versions` workflow opens this PR every Monday.
  It runs `.github/scripts/bump-versions.sh`, then `bump-pr.sh`.
  It uses `RELEASE_TOKEN`, so CI runs on the PR.
  It also starts the distros workflow on the PR's branch.
  To get a bump PR now, run the workflow from the Actions tab.
- Before you merge a bump PR, check the distros run and the list of changes.
  The same version with new checksums means the project replaced a release's files.
- A bump PR is a `fix(installers): ...`, so it makes a release.
- `RELEASE_TOKEN` needs write access to Contents, Pull requests and Actions.
- Download the build for the machine's architecture.
  `envsetup::arch` returns `amd64` or `arm64`.
- Run steps that need root through `envsetup::as_root`.
  It uses sudo or doas, or runs the step directly when the user is already root.
- Write a comment for any other assumption about the OS or architecture.

## Where new content goes

- A shell alias, export or function for every user goes in `shell/shared/`.
- One for a single profile goes in `shell/profiles/<profile>/`.
- Both bash and zsh source everything under `shell/`.
  Any profile can opt in to zsh.
- Some code works only in bash, such as arrays, `mapfile` and bash prompt escapes.
  Put it in a file that starts with `[[ -n "${BASH_VERSION:-}" ]] || return 0`.
  `shell/shared/ps1.sh` is an example.
- An alias or export that needs an optional tool exists only when that tool is installed.
  See `bat` in `shell/shared/aliases.sh`.
  Work lite installs nothing.
  A `cat` alias that points at a missing program breaks `cat` itself.
- Some tools install by name from the distros' package managers.
  List them in `packages/common.txt` or `packages/<profile>.txt`, by their Debian or Ubuntu name.
  Another package manager may use a different name, or may include the tool in its base system.
  The other managers are `dnf`, `zypper`, `pacman`, `apk`, `brew` and `nix`.
  In those cases, add a row to `packages/names.txt`.
- Everything else goes in `installers/common/` or `installers/<profile>/`.
  Examples are a vendor's install script, a binary download and a custom setup step.
- Some popular tools suit only some users, and major distros (Ubuntu LTS, Fedora) do not package them.
  Those go in `installers/extras/`.
  A user opts in to each one by name with `ENVSETUP_EXTRAS`.
  Extras are pinned and checked like every installer (see above).
- A tool that needs a shell hook goes in `shell/shared/tools.sh`.
  direnv and zoxide are examples.
  The hook runs only when the tool is installed.
- A shared git setting or alias goes in `git/gitconfig`, unless it is about identity.
  `lib/git.sh` merges this file with the user's `ENVSETUP_GIT_CONFIG` into `~/.config/envsetup/gitconfig`.
- Identity means `user.name` and `user.email`.
  envsetup asks for them at runtime, or the user sets them in their own `config.sh`.
  Never commit them to this repo.
- Settings for one *user* never go in a tracked file.
  They belong in that user's `~/.config/envsetup/config.sh`.
  `config.example.sh` is the template.
- An update erases edits to tracked files.
  `install.sh` deletes its download.
  "Link shell config" replaces the copy of `shell/`.
- New shells get a copy of `shell/` only.
  The rest of the repo is gone when `install.sh` ends.
  So nothing under `shell/` may read a file outside `shell/`, such as `lib/`, `git/` or `installers/`.
  A menu action generates anything else a shell needs into `$ENVSETUP_STATE`.
  `xdg.sh` is an example.
- The `ENVSETUP_*` variables in `config.sh` are part of the interface that users rely on.
  A new setting gets its default in `envsetup::load_config` (`lib/config.sh`).
  Document it in `config.example.sh`, in the README's settings table and in `docs/interface.md`.
- A setting with a new meaning breaks users' configs.
  So that change is a `!` change.
- A renamed setting gets an item in `ENVSETUP_RENAMED` (`lib/config.sh`).
  Then envsetup still reads the old name and asks to migrate `config.sh`.
  So that rename is not a `!` change.
  A rename without that item is a `!` change.
  Code under `shell/` does not read `ENVSETUP_RENAMED`.
  So code under `shell/` must read both the old name and the new name.
- `work`'s `lite` mode skips `packages/work.txt` and `installers/work/` completely.
  Lite mode does not assume sudo.
  So do not add something to either one that lite mode needs.
  Put it in `shell/shared/` or `shell/profiles/work/` instead.
- Lite mode still runs `lib/git.sh`.
  That file writes only to `$HOME/.gitconfig`, so it needs no sudo.

## Testing

CI (`.github/workflows/ci.yml`) runs two jobs on every push and PR.
On pushes to `main`, it also runs `release` after those jobs pass (see Releases).
`.github/workflows/commits.yml` checks the commit messages and the PR title on every PR.

- `shell-checks` runs `shellcheck` and `shfmt` on every `*.sh` file.
  It also runs `tests/release.sh`.
  That script tests the release flow against a local test remote with the hash-locked commitizen.
  To run it locally, put `cz` on your PATH.
- `smoke` runs `tests/smoke.sh` in a bare `ubuntu:24.04` container.
  It runs these scenarios in order:
  - `install.sh` stops on macOS.
  - `install.sh` stops on a machine without git.
  - It picks a release, then switches to another one.
  - It runs "Run everything" for every profile.
  - It updates from the last 0.x release with the same `config.sh`.
  - A real bash and a real zsh load the result.
- The smoke test replaces only gum's menus, package installs and vendor downloads with fakes.
  So it takes about 15 seconds.
- CI runs the smoke test offline.
  It uses cached copies of the few packages that it installs with real apt.
  Ubuntu's package servers are often slow from CI.
- To run the smoke test locally, run `docker run --rm -t -v "$PWD:/src:ro" ubuntu:24.04 bash /src/tests/smoke.sh`.
- A new menu action, profile or mode needs a scenario in the smoke test.
- Every check must be able to fail.
  Compare against an expected value that is not empty.
  Never compare two values that could both be empty.

The CI badge in `README.md` names `ci.yml` in its image URL and in its link URL.
If you rename `ci.yml`, update both URLs.

The README shows `docs/tapes/demo.gif`.
VHS records it from `docs/tapes/demo.tape`, a script of keystrokes.
Record it again after a release that changes the menu.
The GIF shows the newest release, so its header names a release.
Run these commands from the repo root:

```sh
release=$(mktemp -d) && chmod 755 "$release"
git clone --quiet --depth 1 --branch "$(git describe --tags --abbrev=0 origin/main)" "file://$PWD" "$release"
docker run --rm --hostname demo -v "$PWD:/vhs" -v "$release:/release:ro" -v "$(command -v gum):/usr/local/bin/gum:ro" ghcr.io/charmbracelet/vhs:v0.10.0 docs/tapes/demo.tape
rm -rf "$release"
```

The commands need a gum binary that runs on Linux without other files.
The release binary that envsetup installs works.
The tape runs a dry run in the container, so it changes nothing on your machine.
The hostname `demo` and the user `me` keep your own names out of the GIF.

`tests/distros/run.sh` runs the real tool on a dozen distros with real installs.
It does not run on every push (see `CONTRIBUTING.md`).
The `distros` workflow runs it every week and opens an issue when the run fails.
You can also start it from the Actions tab.
Run it after you change anything that depends on the distro.
Examples are the package lists, `envsetup::pkg_install`, `envsetup::pkg_manager`, the installers and `install.sh`.

The smoke test and the distros test share one fake gum, `tests/gum.sh`.
It reads its answers from `$SMOKE_CHOICES` and `$SMOKE_CONFIRMS`.
It logs each call to `$SMOKE_LOG`.
Extend this file instead of writing a new fake.

The smoke test proves that the flows run.
It does not prove every branch.
So you still check the behavior yourself and describe it in the PR:

- Run `bash -n` and `shellcheck` on every script you change or add.
  CI checks this again, but catch problems before you push.
- Run the functions themselves (`source` them, do not just read them).
  Use fake versions of external commands: `curl`, `sudo`, `gum`, `git` and package managers.
  Use a separate `$HOME`.
- Do not use real networks, install real system packages, or change the real shell or system during a test.
- Some steps are safe to run more than once.
  For each one, test the path where the work is already done.
  Also test the path where the step has work to do.
- If you change `setup.sh` or the menu, also run `tests/smoke.sh` locally (see the command above).
  It drives the real `./setup.sh` from start to end, each time from a fresh `$HOME`.
  Function tests alone once missed a bug: `setup.sh` exited before the menu on every first run.
- Testing is local, and you throw it away afterwards.
  So a test must never change a PR or a commit, and it must never call the GitHub API.
