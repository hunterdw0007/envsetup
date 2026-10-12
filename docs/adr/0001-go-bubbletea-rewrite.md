# ADR 0001: Replace the Bash and gum architecture of envsetup with a Go program that uses Bubble Tea and Bubbles

| | |
| --- | --- |
| Status | Proposed |
| Date | 2026-10-09 |
| Applicable to | v0.1.0 (`127f5ed`) |
| Decision by | Maintainer |
| Language | ASD-STE100 Simplified Technical English |

This ADR uses ASD-STE100 Simplified Technical English. Names of software, files,
commands and computer processes are technical names and technical verbs. Some concepts
have no approved word. For these concepts, the text uses the most clear word that is
available.

## Summary

envsetup has approximately 1,300 lines of Bash in `setup.sh`, `install.sh` and `lib/`.
This Bash code starts [gum](https://github.com/charmbracelet/gum) as a separate process
for each prompt. The repository also has 224 lines of installer scripts, 482 lines of
shell configuration in `shell/`, and 1,445 lines of test scripts. This ADR examines a
change to one Go program that uses [Bubble Tea](https://github.com/charmbracelet/bubbletea)
and [Bubbles](https://github.com/charmbracelet/bubbles) directly. It tells what work is
necessary, what the change gives, and what the change costs.

- **It is not possible to replace all the shell code.** Approximately 40% of the shell
  code must be shell code after the change. These parts must be shell code:
  - The bootstrap script, `install.sh`.
  - The files that the shell of the user loads (`shell/`).
  - The `config.sh` file of the user.
  - The installer scripts, and `lib/common.sh`, which the installer scripts of users can
    load.

  After the change, the repository will contain Go code and Bash code.
- **The best results are in the structure of the code:**
  - One core makes a plan first. Then the core does the changes in the plan. With this
    core, a dry run cannot change the machine. Now, the menu, the steps and the
    uninstall procedure have 25 `envsetup::dry_run` checks that a person must write by
    hand.
  - A headless mode replaces the gum stubs that the tests use now.
  - Go removes the second start under bash 4 on macOS, the `set -e` problems and the gum
    bootstrap.
  - The menu can show the progress of each item. The user can examine and change the
    plan before envsetup does it.
- **The largest costs are not in the user interface:**
  - A procedure that builds and releases a binary for each platform.
  - A decision about `config.sh`. This file is a Bash program and also a documented
    interface for users.
  - Sudo prompts and interactive child processes while a full-screen TUI uses the
    terminal.
  - New versions of the three end-to-end test scripts. Now, these scripts use a fake gum
    to operate the menu.
- **Quantity of work:** approximately 22 to 37 days of work (5 to 8 weeks) for one person
  who knows Go and this repository. Approximately 4,000 to 7,000 lines of Go, with tests,
  replace approximately 1,100 lines of Bash. The test scripts also must have large
  changes.
- **Recommendation:** Do not replace all the code at one time. If the maintainer wants
  the results in this ADR, do the change in stages behind `./setup.sh` (Stages 0 to 4 in
  [Quantity of work](#quantity-of-work)). First, release the build procedure and a
  headless Go core. Replace gum at the end. Before the change, use the gum functions in
  [Method B](#method-b-keep-bash-and-use-more-gum-functions). These functions give
  approximately one third of the visible results for 3 to 6 days of work.

## Condition of envsetup at v0.1.0

### Structure

```
curl | bash
   └─ install.sh            operates in bash 3.2; installs git, clones, checks out the newest vX.Y.Z tag
        └─ setup.sh         parses options (bash 3.2), starts again under bash 4 or newer, installs gum
             ├─ lib/config.sh     loads the defaults and ~/.config/envsetup/config.sh (bash)
             ├─ menu loop         gum choose → case on the text of the selected label
             └─ steps             link rc files · configure git · install packages ·
                                  run installers/*.sh · zsh/oh-my-zsh · XDG moves · uninstall
shell of the user
   └─ rc block → shell/init.sh → shell/shared/*.sh, shell/profiles/<p>/*.sh, config.sh
```

| Area | Files | Lines | Function |
| --- | --- | --- | --- |
| Entry points | `install.sh`, `setup.sh` | 505 | Bootstrap, options, menu, rc links, packages, profile selection |
| Logic | `lib/*.sh` | 814 | Platform detection, package managers, gum bootstrap, git, zsh, XDG, uninstall |
| Installers | `installers/{work,home,extras}/*.sh` | 224 | Separate installer scripts. Each script does nothing if its tool is installed |
| Shell of the user | `shell/**` | 482 | Prompt, aliases, exports, shell functions, tool hooks. Bash and zsh load these files |
| Data | `packages/*.txt`, `git/gitconfig`, `config.example.sh` | — | Package lists, package names for each manager, git defaults |
| Tests | `tests/smoke.sh`, `tests/macos.sh`, `tests/distros/*`, `tests/release.sh` | 1,445 | End-to-end tests. A stub replaces gum through `PATH` |

### How envsetup uses gum

| Call | Quantity | Function |
| --- | --- | --- |
| `gum choose` | 3 | Main menu, profile selection, mode selection |
| `gum confirm` | 6 | EPEL, login shell, XDG moves, uninstall (3 times) |
| `gum input` | 1 | git `user.name` and `user.email` |
| `gum style` | 46 | All lines of status output |

The user interface is a loop of separate prompt processes and styled `echo` lines. Each
prompt is a separate program. The output of the work between the prompts (apt output,
installer output) moves up the screen between the prompts. This structure causes two
results that are important for this ADR:

1. The program sends its state through text strings. The menu selects the action from
   the text of the label (`case "$choice" in "Select profile"*`). The selection lists
   use `"<value>  <description>"` lines, and the code keeps the text before the first
   space. The cause is that only new gum versions have `--label-delimiter` (AGENTS.md).
2. The tests connect to the program through gum. `tests/smoke.sh`, `tests/macos.sh` and
   `tests/distros/scenarios.sh` each put a fake `gum` on `PATH`. The fake `gum` gives
   answers from a queue and records each call. Many checks read this record
   (`grep '^gum choose Select profile'`).

### Previous changes

On 2026-09-22, the project changed to Bash and gum (`d3785ed`, "feat!: rewrite to use
gum with bash"). Between that date and v0.1.0 (2026-10-07), approximately 30 PRs were
merged. Many of these PRs correct problems on specific Linux distributions:

- EPEL on RHEL and its clones.
- `pacman -Syu` on images that have no package lists.
- An `apt-get update` that fails.
- `curl-minimal` on Amazon Linux.
- nix `profile` and `nix-env`.
- A read-only `/usr` on immutable distributions.
- `doas` on Alpine.
- BSD tools on macOS.

The change in this ADR is the second full change in approximately three weeks. These
corrections are the most important part of the repository. A new version of the code
can easily lose them.

### gum uses Bubble Tea

gum is a CLI program that uses Bubble Tea, Bubbles, Lip Gloss and Huh. Thus, the
question is not "gum or Bubble Tea". There are two possible methods. Bash can continue
to control a Bubble Tea program that another team built. Or we can write our own Bubble
Tea program. Our own program must also do the control logic in Go. Bash cannot control a
Bubble Tea program in a different way.

Condition of the libraries in October 2026:

- Version 2 of Bubble Tea, Bubbles, Lip Gloss and Huh became stable in February 2026.
- Version 2 uses new import paths (`charm.land/bubbletea/v2`, `charm.land/bubbles/v2`).
- The latest releases are Bubble Tea v2.0.x and Bubbles v2.1.x.
- Version 2 changed core signatures. For example, `View` gives a view struct, not a
  string. Thus, many examples and blog posts for version 1 are not correct for
  version 2.

## Conditions that the decision must satisfy

1. **One `curl | bash` line installs envsetup on a new machine.** The machine can have no
   git, no gum and only the bash 3.2 of macOS. The tool itself must not use sudo.
2. **Platforms:** apt, dnf (with EPEL), zypper, pacman, apk, Homebrew (Linux and macOS),
   nix, immutable distributions, amd64 and arm64.
3. **Interfaces that users know.** A change to one of these interfaces is a `!` change:
   - `config.sh` is Bash. It uses `+=` and can do tests on `$ENVSETUP_PROFILE`.
   - The `ENVSETUP_*` variables.
   - `ENVSETUP_INSTALLER_DIRS` with scripts that users write.
   - `ENVSETUP_VERSION` with a tag, a branch or a commit.
   - The `./setup.sh`, `--dry-run` and `--uninstall` commands.
4. **Rules from AGENTS.md:**
   - A dry run writes nothing.
   - The uninstall procedure removes all the files and lines that envsetup wrote. It asks
     before it changes an item that the user owns.
   - If one step fails, the other steps continue.
5. **Maintenance by one maintainer.** Contributors who know shell better than Go must
   also be able to help.
6. **Security of the release procedure.** The job that can push to `main` uses only
   hash-locked tools. Each download has a checksum check.

## Limits of the change

| Component | Can Go replace it? | Result |
| --- | --- | --- |
| `setup.sh` menu, options, state | Yes | **Go** |
| `lib/config.sh` (load, resolve, skip) | Only partially. `config.sh` itself is a Bash program | **Go. Bash continues to evaluate `config.sh`** (refer to [Configuration](#configuration)) |
| `lib/common.sh`: platform detection, package managers, downloads, checksums | Yes | **Go.** Keep a small `lib/common.sh` (`has_cmd`, `as_root`, `arch`, `os_release`, `pkg_manager`, `pkg_install`, `release_sha256`, `install_release`). The README tells users to load it in their own installer scripts |
| `lib/git.sh`, `lib/zsh.sh`, `lib/uninstall.sh`, `lib/installers.sh` | Yes. Go continues to start `git`, `chsh` and the oh-my-zsh installer | **Go** |
| `lib/xdg.sh` | Yes. Go is simpler here because it can parse JSON. The `jq` tool is then not necessary | **Go** |
| `install.sh` | No. It must operate before all other parts are on the machine | **Bash 3.2.** The new version downloads the binary |
| `shell/**` | No. The bash or zsh shell of the user loads these files | **Shell, with no change** |
| `installers/**/*.sh` | The installers in this repository: yes. The installers of users: no | **Bash** (the interface). Go versions of the built-in installers are possible after the change |
| `packages/*.txt`, `names.txt`, `git/gitconfig` | Data | **Same format.** Go reads these files and embeds them in the binary |
| `tests/smoke.sh`, `tests/macos.sh`, `tests/distros/*` | These tests use a gum stub | **New versions** that use a headless mode and `teatest` |
| `tests/release.sh`, `.github/scripts/release.sh` | — | **More functions**: build and publish the binaries |

Thus, approximately 1,100 of the 1,543 lines of Bash change to Go. The other shell code
stays, and the repository will have two languages. The shell rules in AGENTS.md
continue for the shell code. New Go rules (`gofmt`, `go vet`, a linter, error wrapping)
are also necessary.

## Proposed architecture (if the maintainer accepts the change)

### Structure of the binary

```
cmd/envsetup/            main: options (stdlib flag; cobra is not necessary for 4 options and 3 subcommands)
internal/platform/       os-release, arch, read-only /usr, package-manager detection
internal/config/         evaluates config.sh with bash, resolves packages, installers and skips
internal/pkgs/           names.txt mapping, install commands for each manager (apt to nix), EPEL
internal/plan/           Change types: Describe() for the dry run, Apply(ctx) for the actual run
internal/steps/          rc links, git, packages, installers, zsh, xdg, uninstall: each gives []plan.Change
internal/runner/         exec with sudo or doas, output capture, log file, sudo keep-alive
internal/state/          profile and mode files in ~/.config/envsetup
internal/tui/            Bubble Tea models: menu, selection lists, plan review, progress, prompts
assets/                  go:embed of shell/, packages/, git/, installers/, config.example.sh
setup.sh                 a small bash 3.2 script that starts the binary (./setup.sh continues to operate)
```

Subcommands:

- `envsetup` starts the TUI. This is the default.
- `envsetup plan [--json]` shows the plan.
- `envsetup apply [--profile P --mode M --yes]` does the plan with no prompts.
- `envsetup uninstall` removes envsetup.
- `envsetup version` shows the version.

### Plan and apply core: a dry run that cannot write

Now, each step does its own check for a dry run. Each step also has a line that a person
wrote by hand to tell the change (`envsetup::would`). The code has 25 `dry_run` checks
and 20 `would` lines. One function of the smoke test is to find a missed check: it
compares two copies of `$HOME`.

In Go, each step only makes a plan:

```go
type Change interface {
	Describe() string                  // "add a 4-line block to ~/.bashrc that loads shell/ from …"
	NeedsRoot() bool
	Apply(ctx context.Context, r *runner.Runner) error
}
```

The dry run, "Preview everything", the plan review screen and `plan --json` all show the
same `[]Change`. An actual run applies the same `[]Change`. A step cannot write without
a `Change`. Thus, a missed dry-run check cannot occur. Some steps must ask the user
before they can make a plan (git identity, which XDG moves to accept). These steps ask
when envsetup makes the plan. Thus, the plan is complete before a change starts.

Some data is only known after other changes are complete. For example, `chsh` is
possibly not installed until the package step is complete. These steps make their plan
again when their time comes. The guarantee does not change. But the preview is only a
forecast, which is also true now.

### TUI: Bubble Tea and Bubbles components

| Now | Bubble Tea, Bubbles, Lip Gloss, Huh |
| --- | --- |
| `gum choose` main menu, selection from the label text | `bubbles/list` with typed items (`Title`, `Description`, an action value). The menu selects from the value, not the label |
| Profile and mode selection with `"value  description"` lines | `list.Item` with a description from the resolved configuration. The code does not cut the first word from the line |
| `gum confirm` | `huh` `Confirm`, or a custom model of approximately 30 lines. Bubbles has no confirm component |
| `gum input` (git identity) | `bubbles/textinput` with validation (not empty, correct email format) |
| `gum style` status lines | Lip Gloss styles. The colors change for light and dark backgrounds |
| apt and installer output that moves up between prompts | One `bubbles/viewport` for each step (the user can close it), one `bubbles/spinner` for each item, one `bubbles/progress` for each step |
| Welcome box, `--help` | Header and footer layout. `bubbles/help` and `bubbles/key` show the keys |
| "Preview everything" as printed text | Plan review screen: a `bubbles/list` or `bubbles/table` of changes. The user can select or deselect each change |
| "Edit config" starts `$EDITOR` | `tea.ExecProcess` stops the TUI, starts the editor, then starts the TUI again and loads the configuration again |

Use inline rendering as the default, not the alternate screen. Then the output of the run
stays in the scrollback after the program stops. Also print a summary as plain text when
the program stops.

### Child processes under a TUI

This part of the change is the most difficult. gum did not have this problem, because
gum stops before the work starts.

- **sudo and doas password prompts.**
  - If a child process reads the terminal while the TUI shows, the screen becomes
    incorrect.
  - Before the first change that has `NeedsRoot()`, start `sudo -v` through
    `tea.ExecProcess`. The TUI stops, and sudo shows its usual prompt.
  - Then, in the background, start `sudo -n -v` again each 60 seconds.
  - `doas` has no `-v` option. Thus, on Alpine, each root command uses `ExecProcess` and
    the TUI shows no progress for it.
  - Do not get the password in a `textinput` and send it to `sudo -S`. This puts the
    password of the user in our process.
- **Interactive child processes.** These programs use `ExecProcess`: `chsh` (on most
  Linux systems, PAM asks for a password), the Homebrew installer, the oh-my-zsh
  installer and `$EDITOR`. All other programs get `stdin=/dev/null` and the
  non-interactive options that they use now (`-y`, `--noconfirm`, `--non-interactive`).
  Debconf also gets `DEBIAN_FRONTEND=noninteractive`.
- **Output capture.** Many tools change their output when it goes into a pipe. For
  example, they remove colors, and apt shows a warning about its CLI. Thus, start child
  processes through a PTY (`github.com/creack/pty`). Then the viewport shows the correct
  output. Also write the output to a log file in `~/.local/state/envsetup/logs/`. The
  uninstall procedure must remove these log files (AGENTS.md: uninstall removes all
  files that envsetup writes).
- **Cancel.** Ctrl+C cancels a `context.Context`. This stops the process group of the
  child and marks the step as failed. The program does not stop.
- **Parallel work.** Package installs stay serial. The cause is the dpkg and rpm locks.
  Also, if envsetup installs one package at a time, one bad package cannot stop all the
  other packages. Vendor downloads can occur in parallel. But the installers are scripts that
  can start sudo or the package manager. Thus, only built-in Go installers are safe for
  parallel work.

### Configuration

`config.sh` is Bash. setup and each interactive shell load it. It uses `+=` on arrays,
and it can do tests on the profile. It is a documented interface. These are the
possible methods:

| Method | Keeps the interface | TUI can edit the configuration | Cost |
| --- | --- | --- | --- |
| **A. Bash evaluates it.** Go starts `bash -c` with the defaults, the profile and the mode in the environment. Bash loads `config.sh` and prints each `ENVSETUP_*` array, with NUL between the values | Yes | No. The user continues to edit it with `$EDITOR` | Small. The script must operate in bash 3.2 (`/bin/bash` on macOS). It must accept a configuration that is not strict, as `load_config` does now |
| B. Change to TOML or YAML, with one table for each profile. Aliases and similar items stay in a shell file | No. This is a `feat!` change, and all users must change their configuration | Yes | Two configuration files, a migration command, and no free logic |
| C. Method A, and a TUI that edits a generated, fenced section of `config.sh` | Yes | Partially | It is not safe to write into a Bash file of a user. The generated section must be last, and this can surprise users |

Recommendation: **method A**. It keeps the interface, and no migration is necessary.
But Go never edits the configuration of the user. Thus, the configuration editor in
[New functions](#new-functions-that-the-change-makes-possible) is not in the scope of
this change. Method B is possible later, as a separate `!` decision.

### Distribution and bootstrap

| Method | Notes |
| --- | --- |
| Build from source on the machine | Each machine must have a Go toolchain. Not accepted |
| **Prebuilt static binaries in each GitHub release** | With `CGO_ENABLED=0`, one binary operates on glibc and musl (Alpine). Platforms: linux/amd64, linux/arm64, darwin/amd64, darwin/arm64. Also linux/arm/v7 if envsetup continues to support armv7 (`gum_release` supports it now). Each binary is approximately 8 to 12 MB. This is almost the same as the gum download that it replaces |

The new `install.sh` installs the macOS Command Line Tools and Homebrew. macOS still
needs Homebrew for packages. But the menu does not need the bash of Homebrew. Then
`install.sh` does these steps:

1. Find the version.
2. Download `envsetup_<os>_<arch>.tar.gz` and `checksums.txt` from that release.
3. Do a check of the checksum.
4. Install the binary in `~/.local/bin`. This needs no sudo, the same as gum now.
5. Start `exec envsetup "$@" </dev/tty`.

Bubble Tea also has an option for TTY input. But keep the redirect.

The change makes these decisions necessary:

- **Git checkout or embedded assets.**
  - If the binary embeds `shell/`, the rc block cannot point to
    `~/envsetup/shell/init.sh`.
  - The binary must extract its assets to `~/.local/share/envsetup/<version>/`, and the
    rc block must point there.
  - This changes `$ENVSETUP_ROOT`. The `config.sh` files and installers of users can use
    this variable. Thus, this is a `!` change, and it needs a migration. The migration
    changes the rc block on the first run.
  - If envsetup keeps the git clone with the binary, no migration is necessary. But then
    there are two items that must agree.
- **`ENVSETUP_VERSION=main` or a commit.** There is no prebuilt binary for these. There
  are three methods:
  - (a) CI builds a snapshot binary for each commit on `main`, and publishes it to an
    `edge` pre-release.
  - (b) If Go is installed, envsetup uses `go build`.
  - (c) Remove this function. This is a `!` change.

  Recommendation: (a) and (b).
- **macOS Gatekeeper.** curl does not set the quarantine attribute. Thus, a binary that
  `install.sh` downloads can operate without a signature. Gatekeeper stops a binary that
  a browser downloads. The usual installation does not need notarization. But the
  README must tell users about this.
- **Checks.** `checksums.txt` and the binary come from the same location. GitHub
  artifact attestations (`actions/attest-build-provenance`, which `gh attestation verify`
  can check) also give provenance. Their cost is small.

### Release procedure

Now, the `release` job starts `release.sh bump` (hash-locked commitizen, no token). Then
it starts `release.sh publish` (push and `gh release create`, no commitizen). Binaries
add a build step. Two conditions control this step:

1. **A tag that `GITHUB_TOKEN` pushes does not start other workflows.** Thus, a build
   workflow with `on: push: tags` never starts. The build must be in the same workflow
   run.
2. **The job that can push to `main` must not start third-party code that is not
   locked** (AGENTS.md). The Go toolchain, goreleaser and module downloads are all new
   code in that job.

Procedure:

1. A separate `build` job, with `contents: read`, starts after the checks.
2. The job finds the version with `cz bump --get-next`.
3. The job builds with `-trimpath -ldflags "-X main.version=…"` and a pinned Go version.
   The bump commit changes only `CHANGELOG.md`, so the code is the same.
4. The job uploads the binaries and `checksums.txt` as workflow artifacts.
5. The `release` job downloads them, and `publish` starts `gh release upload`.

With this procedure, the token is never in the build job. Do not use goreleaser. A
`go build` matrix is approximately 20 lines and adds no dependency.

`tests/release.sh` must also test the asset upload: the first release, a second run when
some assets are not there, and a race. Dependabot must also examine the `gomod` ecosystem. `go.sum`
gives the hash lock for the Go dependencies.

### Tests

| Now | After the change |
| --- | --- |
| No unit tests. A person loads and tests functions by hand | `go test` table tests: `names.txt` mapping, os-release and `/proc/mounts` parsing, checksum file formats, XDG notes, a plan for each profile, mode and OS. The tests use `fs.FS` fakes and a fake runner |
| A gum stub on `PATH` gives answers from a queue. The checks read the `gum …` log lines | `teatest` tests the TUI models (golden output, scripted keys). End-to-end tests use `envsetup apply --yes` and `plan --json` in the same containers |
| A copy of `$HOME` finds a missed dry-run check | This check stays as a black-box check. The plan and apply core also prevents the problem |
| bash 3.2 checks of `setup.sh` | Only `install.sh`, the small `setup.sh`, `shell/` and `lib/common.sh` |

The smoke job builds the linux/amd64 binary on the runner and mounts it into the offline
container. Keep one end-to-end test through a PTY. This test makes sure that the actual
TUI starts, shows the menu and stops. The cause: function tests once did not find that
`setup.sh` stopped before the menu on each first run (AGENTS.md). `tests/macos.sh` and
`tests/distros/*` change to the headless mode. They continue to do actual installs on
actual distributions.

## New functions that the change makes possible

The "Possible now?" column is strict. Gum can do some of these functions partially, and
the column tells this.

| Function | Description | Possible now? |
| --- | --- | --- |
| **One screen for all the work** | Header (version, profile, dry-run mark), menu, a panel with details of the selected action, a footer with the keys. The layout changes with the size of the terminal | No. Each gum call is a separate program, and the output moves up the screen between the calls |
| **Progress for each item** | "Install packages" shows the condition of each package: not started, started, complete or failed. A progress bar shows the total. The output of each step is in a closed viewport. If the step fails, the viewport opens | No. `gum spin` is for one command only, and it does not show the output |
| **Plan review before the changes** | "Preview everything" shows a tree of all the changes, in groups for each step. A mark shows each change that needs sudo. The user can deselect items for this run. Then envsetup does only the selected items | Partially. `gum choose --no-limit` can select items from a flat list. But the list is not the plan that the run does |
| **Headless mode** | `envsetup apply --profile work --mode lite --yes`, and `plan --json` for cloud-init, Dockerfiles, Ansible and CI | Possible in Bash, but the code does not have it. The tests use a fake gum because there is no headless mode. With the plan and apply core, this function is almost free |
| **Status panel** | Which packages, installers and extras are installed or not installed. Which rc files have a link. The git include. The XDG moves. A newer release, if one is available. The user can update the panel | A static version is possible with `gum table` |
| **Exact error reports** | The step and item that failed, the exit code, the last lines of output and the path to the full log. The user can do that item again | Partially. Now, the message is "That step didn't finish; see above" |
| **Cancel a step** | Ctrl+C stops the child process and goes back to the menu | No. Ctrl+C stops the full script in the middle of the step |
| **Lists with search** | Lists of `installers/extras/` and of the 600+ xdg-ninja programs, with a filter, descriptions and the condition of each item | Partially, with `gum filter` |
| **Diff before a write** | A diff of the rc block, the `~/.gitconfig` include and the generated gitconfig before envsetup writes them | Possible with `gum pager` and `diff` |
| **Self-update** | At the start: "v0.3.0 is available. Update now?" envsetup downloads the release, does a check of it and starts again | Possible in Bash. Easier with a binary |
| **Parallel downloads (built-in)** | kubectl, helm, terraform and yq download while the packages install | Not with a clear user interface |
| **Configuration editor** | A form for the `ENVSETUP_*` settings, with validation | Only with configuration method B. Not in scope with method A |
| **Mouse, colors, accessibility** | Click to select. Colors for light and dark backgrounds. `--plain`, `NO_COLOR` or `TERM=dumb` change to line prompts | Partially (gum obeys `NO_COLOR`) |

The change does not give these functions:

- Windows support. envsetup configures POSIX shells, and WSL operates now.
- A faster start. The start is not slow now.

## Problems that the change removes

| Problem now | Data | After the change |
| --- | --- | --- |
| **bash 3.2 and bash 4** | `need_bash4` starts the script again. `install.sh` installs the bash of Homebrew only for the menu. A CI job does tests for bash 3.2. AGENTS.md has rules about `readarray` and `${arr[@]+…}` | The menu does not need bash. The bash 3.2 rules continue for `install.sh`, `shell/` and `lib/common.sh`. But the bash of Homebrew is not necessary |
| **`set -e` problems** | Two rules in AGENTS.md (a function must not end with `[[ … ]] && x`, and never `step \|\| handle`). The subshell in `run_step`. `lib/zsh.sh` tells that its caller disabled `set -e` | Each function gives an `error` value. The caller examines each `error` value, and thus each step is separate |
| **A person must remember each dry-run check** | 25 checks, 20 `would` lines, and a test that compares two copies of `$HOME` | The structure of the code prevents the problem (refer to the plan and apply core) |
| **gum bootstrap and gum versions** | `ensure_gum` and `gum_release` (approximately 60 lines): Homebrew, the GitHub release, `go install` as a last method, and installs of curl, tar and gzip before gum. Each machine can have a different gum version (refer to the `--label-delimiter` rule) | One artifact. `go.sum` pins the versions of the UI libraries |
| **User interface that uses text strings** | The menu selects the action from the label text. The code cuts the first word from each line of a selection list. The tests check the label text | Typed items. A label can change with no other changes |
| **Bash code that parses data** | `names.txt` columns, `/etc/os-release`, `/proc/mounts`, three checksum formats, the `checksums_hashes_order` file of yq, xdg-ninja JSON through `jq` | `bufio`, `encoding/json`, `crypto/sha256`, `archive/tar`, `net/http`. The XDG function does not need `jq`. On small images, built-in downloads do not need curl, wget, tar or gzip |
| **Too much output text** | `gum style` lines mix with the output of apt and the installers | One viewport for each step, a summary and a log file |
| **No unit tests** | Only end-to-end tests. A person loads and tests functions by hand (AGENTS.md, "Testing") | `go test` with coverage. End-to-end tests continue for the full procedures |

The change does not remove these problems:

- The portability work in `shell/` (BSD `column` and GNU `column`, bash and zsh). This
  code stays shell code.
- The differences between the package managers of the distributions. This logic changes
  to Go, but the differences stay.
- `config.sh` is still Bash.

## Risks and precautions

| # | Risk | Level | Precaution |
| --- | --- | --- | --- |
| 1 | **Loss of the corrections for distributions.** Approximately 30 PRs of special cases are in `lib/common.sh` and the installers | High | Change one function at a time. Write a table test for each correction, with a reference to its PR. Before and after each stage, run `tests/distros/run.sh` and `tests/macos.sh` and compare their reports |
| 2 | **The second full change in approximately three weeks.** Users must adapt again, and other work stops for 5 to 8 weeks | High | Do the change in stages behind `./setup.sh`. You can release each stage separately |
| 3 | **Control of the terminal.** sudo, chsh, installers and editors need the TTY | High | `ExecProcess`, `sudo -v` keep-alive, PTY capture, non-interactive options (refer to [Child processes under a TUI](#child-processes-under-a-tui)). On Alpine, `doas` shows no progress |
| 4 | **Distribution and release procedure.** Binaries for each OS and architecture, attestations, edge builds for `main`, and a token that the toolchain must not get | High | A separate build job with read access only. A `go build` matrix. Tests in `tests/release.sh` |
| 5 | **Two languages in the repository.** Go and Bash have different rules, and contributors must know the two languages | Medium | Keep the Bash code small and stable (`shell/`, `install.sh`, the `lib/common.sh` helper API). Add a Go section to AGENTS.md |
| 6 | **Users cannot easily change the code.** Now, a user can read and change the menu in a shell that they know. A compiled binary is not easy to read | Medium | `config.sh`, user installers and `shell/` stay as the extension points. Write instructions for `go run ./cmd/envsetup` for development |
| 7 | **Bubble Tea v2 is eight months old.** Its import paths changed, and most examples are for v1 | Medium | Pin the versions. Use Dependabot for `gomod`. Use only the core Bubbles components |
| 8 | **More code in a tool that controls sudo.** The binary does not operate as root, but it selects the commands that operate as root | Medium | Use the same model as now (`as_root` for each command). Never touch passwords. Add no new network endpoints. Use attestations |
| 9 | **Full-screen user interfaces are worse than line prompts for screen readers and dumb terminals** | Medium | Inline rendering as the default. A `--plain` mode with line prompts (shared with the headless mode). Obey `NO_COLOR` and `TERM=dumb` |
| 10 | **`$ENVSETUP_ROOT` changes** if the binary embeds and extracts the assets | Medium | Keep the clone in Stages 0 to 3. Make a separate `!` decision for embedded assets, with a migration of the rc block |
| 11 | **`ENVSETUP_VERSION=<branch/commit>`** has no binary | Medium | Edge builds, and `go build` if Go is installed |
| 12 | **End-to-end tests of the TUI are more difficult** than tests with a fake gum | Medium | `teatest` for the models, the headless mode for the procedures, and one PTY smoke test |
| 13 | **Binary size and download time** on slow connections (approximately 8 to 12 MB) | Low | Almost the same as the gum download that it replaces |

## Quantity of work

### Size

| | Now (Bash) | After the change (approximate) |
| --- | --- | --- |
| Code that changes to Go | Approximately 1,100 lines (`setup.sh`, `lib/`, and parts of `install.sh`) | 2,500 to 3,500 lines of Go logic, and 1,000 to 1,500 lines of TUI code |
| Shell code that stays | `shell/` 482, installers 224, `install.sh` approximately 120, a smaller `lib/common.sh` approximately 120, the `setup.sh` script approximately 20 | The same |
| Tests | 1,445 lines of test scripts | 1,500 to 2,500 lines of `go test`. Approximately 50% of the smoke, macOS and distribution test scripts change |
| CI | 3 jobs and the release job | Also `go vet`, a linter and tests, a build matrix job, an asset upload in the release, edge builds |
| Documents | README, AGENTS.md, `--help` | README sections for install, architecture and tests. Go rules in AGENTS.md. Updates to this ADR |

### Stages

Each stage is one PR, or a small stack of PRs, that you can release. After each stage,
`./setup.sh`, `--dry-run`, `--uninstall` and the procedures in the README must
operate.

| Stage | Result | Visible to users | Days of work |
| --- | --- | --- | --- |
| **0. Release procedure** | Go module. `envsetup version`. CI (vet, linter, tests). A build job with read access only. Releases with binaries, checksums and attestations. Edge builds for `main`. `install.sh` downloads the binary and does a check of it, but continues to start the Bash `setup.sh` | No (`ci` and `build` commits) | 3 to 5 |
| **1. Core, read only** | `platform`, `config` (method A), `pkgs` name mapping, `plan` types. `envsetup plan --json` for all steps. A smoke test compares the Go plan with the Bash dry-run output for each profile and mode | No | 4 to 6 |
| **2. Apply, headless** | `runner` (sudo keep-alive, PTY, logs). `Apply` for all steps. Uninstall, with the logs. `envsetup apply --yes`. The distribution and macOS tests use the headless mode, and we compare their reports with the Bash reports | New `apply` command (`feat`) | 6 to 10 |
| **3. TUI** | Bubble Tea program: menu, selection lists, plan review, progress, prompts, `ExecProcess` for the editor and chsh. `teatest` tests. `setup.sh` becomes a small script that starts the binary | Yes: a new user interface (`feat!`: different keys and screens) | 6 to 10 |
| **4. Remove the Bash core** | Remove the gum bootstrap and `lib/*.sh`, but keep the small `lib/common.sh`. Remove the second start under bash 4 and the Homebrew bash. Update the README and AGENTS.md | Yes (`feat!` if an option or a function changes) | 3 to 6 |
| | | **Total** | **22 to 37** |

These numbers are for one person who knows Go well and knows this repository. If the
person must also learn the model of Bubble Tea v2, add approximately 30%. Stages 0 to 2
are useful without the other stages (headless mode, unit tests, a dry run that cannot
write). This is also true if Stage 3 never occurs.

## Other methods that we examined

### Method A: No change

This method costs nothing. All the problems in
[Problems that the change removes](#problems-that-the-change-removes) stay. This method
is satisfactory for a personal tool at v0.1.0. Most of the problems now are for
contributors (the `set -e` and bash 3.2 rules), not for users.

### Method B: Keep Bash and use more gum functions

gum has components that the repository does not use now:

| gum function | Result |
| --- | --- |
| `gum spin --show-output` | A spinner for each long step |
| `gum choose --no-limit` | The user selects which packages, installers and XDG moves to do in this run |
| `gum filter` | A list of extras and xdg-ninja programs, with search |
| `gum table` | Status panel, XDG plan |
| `gum pager` | Diff before a write, step logs |
| `gum log` | Status lines with levels and times, not colors that each line sets |
| `gum format` | Help screens in Markdown |

Also add a `--yes` headless mode, which also makes the tests simpler, and a log file for
each run. This work is approximately 3 to 6 days. It gives approximately one third of
the visible results. It does not correct the problems in the structure: `set -e`,
bash 4, menu selection from text, and dry-run checks that a person must remember.

### Method C: A Go TUI in front of the Bash steps

A small Bubble Tea binary shows a plan and progress. The Bash steps send this data as
JSON lines on a separate channel. This method gives the results in the user interface
with less work. We do not accept it as the final method. It adds a protocol between two
languages. It also keeps all the Bash problems and adds a binary to distribute. It can
be an intermediate step, but Stages 1 and 2 give the same result more directly.

### Method D: Replace the Bash code with Go, Bubble Tea and Bubbles (this proposal)

Refer to the sections above.

### Method E: Other languages

- Rust and ratatui: almost the same advantages and problems. The toolchain is larger.
  The look of gum comes from the Charm libraries, and this method does not use them.
- Python and Textual: a new machine must have a Python runtime. This is not possible for
  the bootstrap.

Go is better than these two methods for envsetup.

## Decision

**Proposed:** Do not replace all the code at one time. Use the gum functions in
[Method B](#method-b-keep-bash-and-use-more-gum-functions) now. Accept the Go and Bubble
Tea change only as the stages in this ADR. Start with Stage 0. Start only if these two
conditions are true:

1. The maintainer wants progress for each item, plan review or the headless mode. The
   maintainer must also agree to stop other work for 5 to 8 weeks.
2. The maintainer makes the decisions in
   [Decisions that are necessary first](#decisions-that-are-necessary-first). Each of
   these decisions changes an interface that users know.

Examine this decision again if one of these conditions occurs:

- A second contributor starts to work on the repository.
- Users want headless installation (cloud-init, CI images).
- Bash bugs from `set -e`, dry-run checks or bash 3.2 compatibility occur again and
  again.

## Results of the decision

If the maintainer accepts the change:

- **Good results:**
  - A dry run that cannot write, a headless mode and unit tests.
  - No bash 4 bootstrap and no gum bootstrap.
  - A user interface that shows progress, plans and errors clearly.
  - Pinned versions of the UI libraries.
- **Bad results:**
  - Two languages in the repository, and a release procedure for binaries.
  - More code in the release procedure.
  - Other work stops for some weeks.
  - A new user interface that users must learn. Thus, the change is `feat!`, and on 0.x
    it increases the minor version.
  - The test scripts change at the same time as the code that they test.
- **No change for users with configuration method A:** `shell/`, installers, `config.sh`
  and the package lists.

## Decisions that are necessary first

1. Configuration: method A (Bash evaluates it, recommended) or method B (data file, `!`)?
2. Keep the git checkout, or embed the assets and change `$ENVSETUP_ROOT`?
3. `ENVSETUP_VERSION=<branch|commit>`: edge builds, `go build` if Go is installed, or
   remove the function?
4. Is linux/arm/v7 still a platform? (The gum bootstrap supports it. `envsetup::arch`
   does not.)
5. Inline rendering or the alternate screen as the default?
6. Do the built-in installers change to Go (parallel, with checksum checks, no curl or
   tar)? Or do they stay as examples of the script interface?

## References

- Bubble Tea releases and the v2 upgrade guide: <https://github.com/charmbracelet/bubbletea/releases>
- Bubbles: <https://github.com/charmbracelet/bubbles>
- gum (it uses the libraries above): <https://github.com/charmbracelet/gum>
- The repository rules that this ADR uses: `AGENTS.md`
- Entry points now: `install.sh`, `setup.sh`, `lib/*.sh`. Test connections now:
  `tests/smoke.sh` (gum stub), `tests/distros/scenarios.sh`, `tests/macos.sh`
