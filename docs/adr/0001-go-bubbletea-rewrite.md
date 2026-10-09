# ADR 0001: Rewrite envsetup as a Go program built on Bubble Tea and Bubbles

| | |
| --- | --- |
| Status | Proposed |
| Date | 2026-10-09 |
| Applies to | v0.1.0 (`127f5ed`) |
| Decision needed from | Maintainer |

## Summary

envsetup is about 1,300 lines of Bash (`setup.sh`, `install.sh`, `lib/`) that drive
[gum](https://github.com/charmbracelet/gum) as a subprocess. Another 220 lines of
installer scripts and 480 lines of `shell/` config sit beside it, along with 1,450 lines
of test harnesses. This ADR estimates what it would take to replace that with one Go
binary that uses [Bubble Tea](https://github.com/charmbracelet/bubbletea) and
[Bubbles](https://github.com/charmbracelet/bubbles) directly. It covers what the
rewrite would gain and what it would cost.

- **Not everything can be rewritten.** About 40% of the shell has to stay shell. That
  includes the bootstrap (`install.sh`), everything sourced into the user's own shell
  (`shell/`), the user's `config.sh`, and the installer-script contract, which includes
  `lib/common.sh` as a helper API for users' own installers. Afterwards the repo would
  use both Go and Bash, not Go only.
- **The biggest gains are structural:**
  - A single plan-then-apply core would make dry-run safe by construction. Today the
    menu, steps and uninstall have 25 hand-written `envsetup::dry_run` guards.
  - A first-class headless mode would replace the gum stubs the tests depend on.
  - Go would remove the macOS bash-3.2/bash-4 re-exec, the `set -e` pitfalls and the
    gum bootstrap.
  - The menu could show live per-item progress, and reviewing and editing the plan
    before running it would become practical.
- **The biggest costs are outside the UI:**
  - A binary distribution and release pipeline.
  - What to do with `config.sh`, which is a bash program and a documented user API.
  - Running sudo and interactive child processes under a full-screen TUI.
  - Rewriting all three end-to-end test harnesses, which drive the menu by faking gum.
- **Lift:** about 22–37 focused days (5–8 weeks) for one person who knows Go and this
  repo. Roughly 4–7k lines of Go including tests would replace about 1.1k lines of
  Bash, and the existing test harnesses would need substantial changes.
- **Recommendation:** don't do a big-bang rewrite now. If the gains below are wanted,
  do a phased migration behind the existing `./setup.sh` entry point (Phases 0–4 under
  [Lift](#lift)). Ship the distribution pipeline and a headless Go core first, and
  replace gum only at the end. Before then, adopt the gum features listed in
  [Alternative B](#b-stay-on-bash-and-use-more-of-gum), which deliver about a third of
  the user-visible gains for a few days' work.

## Context

### What envsetup is today

```
curl | bash
   └─ install.sh            bash 3.2-safe; installs git, clones, checks out newest vX.Y.Z tag
        └─ setup.sh         parses options (3.2-safe), re-execs under bash ≥4, ensures gum
             ├─ lib/config.sh     sources defaults + ~/.config/envsetup/config.sh (bash)
             ├─ menu loop         gum choose → case on the chosen label string
             └─ steps             link rc files · configure git · install packages ·
                                  run installers/*.sh · zsh/oh-my-zsh · XDG moves · uninstall
user's shell
   └─ rc block → shell/init.sh → shell/shared/*.sh, shell/profiles/<p>/*.sh, config.sh
```

| Area | Files | Lines | Role |
| --- | --- | --- | --- |
| Entry points | `install.sh`, `setup.sh` | 505 | bootstrap, option parsing, menu, rc linking, packages, profile picker |
| Logic | `lib/*.sh` | 814 | platform detection, package-manager abstraction, gum bootstrap, git, zsh, XDG, uninstall |
| Installers | `installers/{work,home,extras}/*.sh` | 224 | standalone, idempotent vendor installers |
| User shell | `shell/**` | 482 | prompt, aliases, exports, functions, tool hooks; sourced by bash and zsh |
| Data | `packages/*.txt`, `git/gitconfig`, `config.example.sh` | — | package lists, per-manager names, git defaults |
| Tests | `tests/smoke.sh`, `tests/macos.sh`, `tests/distros/*`, `tests/release.sh` | 1,445 | end-to-end runs with gum stubbed through `PATH` |

### How gum is used

| Call | Count | Used for |
| --- | --- | --- |
| `gum choose` | 3 | main menu, profile picker, mode picker |
| `gum confirm` | 6 | EPEL, login shell, XDG moves, uninstall (×3) |
| `gum input` | 1 | git `user.name` / `user.email` |
| `gum style` | 46 | every line of status output |

The UI is a loop of separate prompt processes plus styled `echo`. Each prompt is its own
program, and the work in between (apt output, installer output) scrolls past between
them. Two consequences matter for this ADR:

1. Program state is passed through strings. Menu dispatch matches label text
   (`case "$choice" in "Select profile"*`). Picker values come from
   `"<value>  <description>"` lines cut at the first space, because
   `--label-delimiter` only exists on newer gum (AGENTS.md).
2. gum is the test seam. `tests/smoke.sh`, `tests/macos.sh` and `tests/distros/scenarios.sh`
   each put a fake `gum` on `PATH` that answers prompts from a queue and logs every call,
   and many checks assert on that log (`grep '^gum choose Select profile'`).

### History

The project was rewritten into Bash + gum on 2026-09-22 (`d3785ed`, "feat!: rewrite to use
gum with bash"). In the two weeks between that and v0.1.0 (2026-10-07), about 30 PRs landed,
many encoding fixes for specific distros (EPEL, pacman `-Syu` on never-synced images,
tolerating a failed `apt-get update`, Amazon Linux's `curl-minimal`, nix `profile` vs
`nix-env`, read-only `/usr` on immutable distros, `doas` on Alpine, BSD tools on macOS).
This would be the second rewrite in about three weeks. Those fixes are the most
valuable thing in the repo and the easiest to lose.

### gum already is Bubble Tea

gum is a CLI wrapper around Bubble Tea, Bubbles, Lip Gloss and Huh. So the question isn't
"gum or Bubble Tea". It is whether to keep orchestrating a prebuilt Bubble Tea program
from Bash, or to write our own Bubble Tea program, which means writing the orchestration
in Go too. A Bubble Tea program can't be driven from Bash any other way.

Current upstream state (October 2026): Bubble Tea, Bubbles, Lip Gloss and Huh v2 went
stable in February 2026 under new vanity import paths (`charm.land/bubbletea/v2`,
`charm.land/bubbles/v2`). The latest releases are Bubble Tea v2.0.x and Bubbles v2.1.x.
v2 changed core signatures (for example, `View` returns a view struct instead of a
string), so v1-era examples and blog posts don't apply as written.

## Decision drivers

1. **Bootstrapping a bare machine with one `curl | bash` line**, with no git, no gum, no
   sudo for the tool itself, and macOS's bash 3.2.
2. **Supported platforms:** apt, dnf (+EPEL), zypper, pacman, apk, Homebrew (Linux and
   macOS), nix, immutable distros, and amd64/arm64.
3. **User-facing contracts:** `config.sh` as bash (`+=`, branching on
   `$ENVSETUP_PROFILE`), `ENVSETUP_*` variables, `ENVSETUP_INSTALLER_DIRS` with
   user-written scripts, `ENVSETUP_VERSION` pinning to tags, branches or commits, and the
   `./setup.sh` and `--dry-run` / `--uninstall` habits. Breaking any of these is a `!`
   change.
4. **Invariants from AGENTS.md:**
   - Dry-run writes nothing.
   - Uninstall removes everything envsetup wrote and asks before touching anything the
     user owns.
   - One failing step doesn't stop the rest.
5. **Maintainability for a single maintainer**, and contributions from people who know
   shell better than Go.
6. **Supply-chain posture:** hash-locked tooling in the job that can push to `main`, and
   checksum-verified downloads.

## Scope: what "completely rewrite" can and can't mean

| Component | Can it move to Go? | Verdict |
| --- | --- | --- |
| `setup.sh` menu, option parsing, state | Yes | **Go** |
| `lib/config.sh` (load, resolve, skip) | Partly: `config.sh` itself is a bash program | **Go, with config.sh still evaluated by bash** (see [Config](#config)) |
| `lib/common.sh` platform detection, package managers, downloads, checksums | Yes | **Go**. Keep a slim `lib/common.sh` (`has_cmd`, `as_root`, `arch`, `os_release`, `pkg_manager`, `pkg_install`, `release_sha256`, `install_release`) because the README tells users' own installers to source it |
| `lib/git.sh`, `lib/zsh.sh`, `lib/uninstall.sh`, `lib/installers.sh` | Yes (still execs `git`, `chsh`, the oh-my-zsh installer) | **Go** |
| `lib/xdg.sh` | Yes, and it's simpler in Go (native JSON, so no `jq` dependency) | **Go** |
| `install.sh` | No: it has to run before anything else exists | **Stays Bash 3.2**, rewritten to fetch the binary |
| `shell/**` | No: sourced into the user's bash/zsh | **Stays shell**, unchanged |
| `installers/**/*.sh` | Built-in ones could, user ones can't | **Stay Bash** (the contract), optionally reimplemented as built-ins later |
| `packages/*.txt`, `names.txt`, `git/gitconfig` | Data | **Same format**, read by Go and embedded in the binary |
| `tests/smoke.sh`, `tests/macos.sh`, `tests/distros/*` | They depend on stubbing gum | **Rewritten** around a headless mode + `teatest` |
| `tests/release.sh`, `.github/scripts/release.sh` | — | **Extended** to build and publish binaries |

So about 1,100 of the roughly 1,540 lines of product Bash move to Go. The rest of the
shell stays, and the repo ends up bilingual. AGENTS.md's shell standards still apply
to what's left, and Go standards (`gofmt`, `go vet`, a linter, error wrapping) are added
on top.

## Proposed architecture (if accepted)

### Binary layout

```
cmd/envsetup/            main: flag parsing (stdlib flag; no cobra needed for 4 options + 3 subcommands)
internal/platform/       os-release, arch, immutable /usr, package-manager detection
internal/config/         evaluate config.sh via bash, resolve packages/installers/skip
internal/pkgs/           names.txt mapping, per-manager install commands (apt…nix), EPEL
internal/plan/           Change types: Describe() for dry-run, Apply(ctx) for real
internal/steps/          shell rc linking, git, packages, installers, zsh, xdg, uninstall: each returns []plan.Change
internal/runner/         exec with sudo/doas, output capture, log file, sudo keep-alive
internal/state/          profile/mode files under ~/.config/envsetup
internal/tui/            Bubble Tea models: menu, pickers, plan review, progress, prompts
assets/                  go:embed of shell/, packages/, git/, installers/, config.example.sh
setup.sh                 kept as a 3.2-safe shim: exec the binary (keeps ./setup.sh working)
```

Subcommands: `envsetup` (TUI, the default), `envsetup plan [--json]`,
`envsetup apply [--profile P --mode M --yes]`, `envsetup uninstall`, and `envsetup version`.

### Plan/apply core: dry-run by construction

Today each step decides on its own whether it's in a dry run, and describes the change in
a hand-written `envsetup::would` line. There are 25 `dry_run` checks and 20 `would` lines.
The smoke test exists partly to catch a missed guard by snapshotting `$HOME`.

In Go, each step only builds a plan:

```go
type Change interface {
	Describe() string                  // "add a 4-line block to ~/.bashrc that loads shell/ from …"
	NeedsRoot() bool
	Apply(ctx context.Context, r *runner.Runner) error
}
```

Dry-run, "Preview everything", the plan-review screen and `plan --json` all render the
same `[]Change`. A real run applies it. A step can't write without a `Change`, so a
missed dry-run guard can't happen. Steps that need input before they can plan (git
identity, which XDG moves to accept) ask at planning time, so the plan is complete
before anything runs.

The caveat is that some state is only known after earlier changes apply. For example,
whether `chsh` is missing depends on whether packages installed. Such steps re-plan when
they reach their turn. That keeps the guarantee, but the preview is a best-effort
forecast, which is also true today.

### TUI: Bubble Tea + Bubbles mapping

| Today | Bubble Tea / Bubbles / Lip Gloss / Huh |
| --- | --- |
| `gum choose` main menu, label-string dispatch | `bubbles/list` with typed items (`Title`, `Description`, an action value); dispatch on the value, not the label |
| profile/mode pickers with `"value  description"` lines | `list.Item` with a real description built from the resolved config; no first-word parsing |
| `gum confirm` | `huh` `Confirm` (or a 30-line custom model; Bubbles has no confirm component) |
| `gum input` (git identity) | `bubbles/textinput` with validation (non-empty, email shape) |
| `gum style` status lines | Lip Gloss styles, adaptive to light/dark backgrounds |
| raw apt/installer output scrolling between prompts | `bubbles/viewport` per step (collapsible), `bubbles/spinner` per item, `bubbles/progress` per step |
| welcome box, `--help` | header/footer layout; `bubbles/help` + `bubbles/key` for the key legend |
| "Preview everything" printed text | plan-review screen: `bubbles/list` / `bubbles/table` of changes, with toggles |
| "Edit config" runs `$EDITOR` | `tea.ExecProcess` suspends the TUI, runs the editor, then resumes and reloads config |

Use inline rendering (not the alt screen) by default, so the run's output stays in
scrollback after exit. Also print a plain-text summary on exit.

### Running child processes under a TUI

This is the hardest engineering part of the rewrite, and the part gum never had to deal
with, because gum exits before any work starts.

- **sudo / doas password prompts.** With a TUI on screen, a child process that reads
  the terminal corrupts it. Plan: before applying any change with `NeedsRoot()`, run
  `sudo -v` through `tea.ExecProcess` (TUI suspended, normal prompt), then refresh it in
  the background with `sudo -n -v` every 60s. `doas` has no `-v` equivalent, so on
  Alpine every root command uses `ExecProcess`, without live progress. Don't collect the
  password in a `textinput` and pipe it to `sudo -S`, because that would put the user's
  password in our process.
- **Interactive children.** `chsh` (PAM asks for a password on most Linux systems), the
  Homebrew installer, the oh-my-zsh installer and `$EDITOR` all go through `ExecProcess`.
  Everything else gets `stdin=/dev/null` plus the non-interactive flags it already uses
  (`-y`, `--noconfirm`, `--non-interactive`), and `DEBIAN_FRONTEND=noninteractive` for
  debconf.
- **Output capture.** Piped output changes behaviour: tools drop color, and apt warns
  about an unstable CLI. Run children through a PTY (`github.com/creack/pty`) for
  faithful output in the viewport, tee'd to a log file under
  `~/.local/state/envsetup/logs/`. That needs uninstall coverage (AGENTS.md: anything
  envsetup writes is removed by uninstall).
- **Cancellation.** Ctrl+C cancels a `context.Context` that kills the child's process
  group and marks the step failed, without exiting the program.
- **Concurrency.** Package-manager installs stay serial (dpkg/rpm locks, and one at a
  time on purpose so one bad package doesn't sink the batch). Vendor downloads can run
  in parallel, but installers are opaque scripts that may call sudo or the package
  manager. Only built-in Go installers would be safe to parallelise.

### Config

`config.sh` is bash. It's sourced by setup and by every interactive shell, uses `+=` on
arrays and branches on profile, and is a documented API. Options:

| Option | Keeps the API | Structured editing in the TUI | Cost |
| --- | --- | --- | --- |
| **A. Evaluate with bash.** Go runs `bash -c` with the defaults and profile/mode in the environment, sources `config.sh`, and prints each `ENVSETUP_*` array NUL-separated | Yes | No (editing stays `$EDITOR`) | Small; the dump script must be 3.2-safe (`/bin/bash` on macOS) and tolerate a non-strict config, as `load_config` does today |
| B. Move to TOML/YAML with per-profile tables; aliases etc. stay in a shell file | No: `feat!`, every user migrates | Yes | Two config files, a migration command, and no arbitrary logic |
| C. A: plus a TUI that edits a generated, fenced section of `config.sh` | Yes | Partly | Writing into a user's bash file is fragile; the generated section must be the last word, which surprises people |

Recommend **A**. It keeps the contract and needs no migration. The trade-off is that
Go never edits user config, so the structured config editor below is out of scope
unless B is taken later as a separate `!` decision.

### Distribution and bootstrap

| Option | Notes |
| --- | --- |
| Build from source on the machine | Needs a Go toolchain on every target. Rejected |
| **Prebuilt static binaries attached to each GitHub release** | `CGO_ENABLED=0`, so one binary runs on glibc and musl (Alpine). Targets: linux/amd64, linux/arm64, darwin/amd64, darwin/arm64 (+ linux/arm/v7 if armv7 stays supported; `gum_release` handles it today). About 8–12 MB each, similar to the gum download it replaces |

`install.sh` becomes: bootstrap macOS CLT + Homebrew (macOS still needs Homebrew for
packages, but no longer needs Homebrew's bash to run the menu). Then:

1. Resolve the version.
2. Download `envsetup_<os>_<arch>.tar.gz` and `checksums.txt` from that release.
3. Verify the checksum.
4. Install to `~/.local/bin` (no sudo, same as gum today).
5. `exec envsetup "$@" </dev/tty`.

Bubble Tea also has a TTY-input option, but keep the redirect.

Decisions this forces:

- **Git checkout or embedded assets.** If `shell/` is embedded, the rc block can't
  point at `~/envsetup/shell/init.sh` any more. The binary extracts its assets to
  `~/.local/share/envsetup/<version>/` and the rc block points there. That changes
  `$ENVSETUP_ROOT`, which users' `config.sh` and installers may reference, so it's a `!`
  change and needs a migration (rewrite the rc block in place on first run). Keeping the
  git clone alongside the binary avoids the migration, but then there are two
  artifacts to keep in sync.
- **`ENVSETUP_VERSION=main` or a commit.** These have no prebuilt binary. The choices
  are: (a) build snapshot binaries for every `main` commit in CI and publish them to a
  rolling `edge` pre-release, (b) fall back to `go build` when Go is installed, or (c)
  drop support, which is a `!` change. Recommend (a)+(b).
- **macOS Gatekeeper.** curl doesn't set the quarantine attribute, so an
  `install.sh`-downloaded binary runs unsigned. A browser download would be blocked.
  Notarization isn't needed for the supported path, but it should be documented.
- **Verification.** `checksums.txt` comes from the same origin as the binary. GitHub
  artifact attestations (`actions/attest-build-provenance`, verifiable with
  `gh attestation verify`) add provenance at little cost.

### Release pipeline

Today, `release` runs `release.sh bump` (hash-locked commitizen, no token), then
`release.sh publish` (push + `gh release create`, no commitizen). Binaries add a build
step, and two constraints shape it:

1. **A tag pushed with `GITHUB_TOKEN` doesn't trigger other workflows**, so an
   `on: push: tags` build workflow would never run. The build has to be part of the same
   run.
2. **The job that can push to `main` must not run unlocked third-party code**
   (AGENTS.md). The Go toolchain, goreleaser if used, and module downloads would all be
   new code in that job.

Plan: a separate `build` job with `contents: read` runs after the checks. It computes the
version with `cz bump --get-next` and builds with `-trimpath -ldflags "-X main.version=…"`
using a pinned Go version. The bump commit changes only `CHANGELOG.md`, so the code is
identical. The job uploads the binaries and `checksums.txt` as workflow artifacts. The
existing `release` job then downloads them and adds `gh release upload` to `publish`.
This keeps the token out of the build. Skip goreleaser: a plain `go build` matrix is
about 20 lines and adds no dependency.

`tests/release.sh` gains the asset-upload paths (first release, re-run with missing
assets, race). Dependabot adds the `gomod` ecosystem. `go.sum` provides the hash lock
for Go dependencies.

### Testing

| Today | After |
| --- | --- |
| No unit tests; functions sourced ad hoc | `go test` table tests: `names.txt` mapping, os-release/`/proc/mounts` parsing, checksum-file formats, XDG note parsing, plan generation per profile/mode/OS, using `fs.FS` fakes and a fake runner |
| gum stub on `PATH` answering prompts from a queue, asserting on `gum …` log lines | TUI models tested with `teatest` (golden output, scripted key presses). End-to-end runs use `envsetup apply --yes` / `plan --json` in the same containers |
| Snapshot of `$HOME` to catch a missed dry-run guard | Kept as a black-box check, now backed by the construction guarantee |
| bash 3.2 checks of `setup.sh` | Shrinks to `install.sh`, the `setup.sh` shim, `shell/`, `lib/common.sh` |

The smoke job builds the linux/amd64 binary on the runner and mounts it into the offline
container. Keep one PTY-driven end-to-end check that the real TUI starts, renders the
menu and quits, because function-level tests once missed that `setup.sh` exited before
the menu on every first run (AGENTS.md). `tests/macos.sh` and `tests/distros/*` switch to
the headless mode. Their value (real installs on real distros) is unchanged.

## Features this would make possible

The "Possible today?" column is deliberately strict. Several items can be approximated
with gum, and the column says so.

| Feature | What it looks like | Possible today? |
| --- | --- | --- |
| **Persistent single-screen app** | Header (version, profile, dry-run badge), menu, details pane for the highlighted action, key-help footer; resizes with the terminal | No. Each gum call is a separate program, with output scrolling in between |
| **Live per-item progress** | "Install packages" shows each package as pending/spinner/✓/✗ with a progress bar; output collapsed into a per-step viewport, expanded on failure | No. `gum spin` wraps one command and hides its output |
| **Plan review before applying** | "Preview everything" becomes an interactive tree of every change, grouped by step, marked as needing sudo or not; deselect items for this run, then apply exactly that | Partly. `gum choose --no-limit` can multi-select a flat list, but not tied to a plan the run then executes |
| **Headless / automation mode** | `envsetup apply --profile work --mode lite --yes`, `plan --json` for cloud-init, Dockerfiles, Ansible, CI | Could be built in Bash, but isn't. The tests fake gum because there is no headless path. The plan/apply split makes it nearly free |
| **Status dashboard** | Which packages/installers/extras are present or missing, which rc files are linked, git include state, XDG moves, newer release available; refreshable | Static version possible with `gum table` |
| **Precise failure reporting** | Failed step and item, exit code, last lines of output, path to the full log; offer to retry just that item | Partly. Today it says "That step didn't finish; see above" |
| **Cancel a running step** | Ctrl+C stops the current child and returns to the menu | No. Ctrl+C kills the whole script mid-step |
| **Searchable catalogues** | Filterable lists of `installers/extras/` and the 600+ xdg-ninja programs, with descriptions and current state | Partly, with `gum filter` |
| **Diff preview** | rc-file block, `~/.gitconfig` include and generated gitconfig shown as a diff before writing | Possible with `gum pager` + `diff` |
| **Self-update** | "v0.3.0 is available: update now?" on launch; downloads, verifies, re-execs | Possible in Bash; easier with the binary model |
| **Parallel built-in downloads** | kubectl/helm/terraform/yq fetched concurrently while packages install | Not with coherent UI |
| **Structured config editor** | Form for `ENVSETUP_*` with validation | Only with config option B; out of scope under A |
| **Mouse, theming, accessibility switches** | Click to select; adaptive colors; `--plain`/`NO_COLOR`/`TERM=dumb` falls back to line prompts | Partly (gum respects `NO_COLOR`) |

Not gained: Windows support (envsetup configures POSIX shells, and WSL already works),
and faster startup (startup isn't a problem today).

## Problems this would solve

| Problem today | Evidence | After |
| --- | --- | --- |
| **bash 3.2 vs 4 split** | `need_bash4` re-exec; `install.sh` installs Homebrew's bash just to run the menu; a CI job for 3.2; AGENTS.md rules on `readarray`, `${arr[@]+…}` | The menu no longer needs bash. Bash 3.2 rules still cover `install.sh`, `shell/` and `lib/common.sh`, but Homebrew bash stops being a prerequisite |
| **`set -e` hazards** | Two AGENTS.md rules (`[[ … ]] && x` endings; never `step \|\| handle`), `run_step`'s subshell dance, and `lib/zsh.sh` documenting that its caller disabled `set -e` | Explicit `error` returns; per-step isolation is just error handling |
| **Dry-run guards are a convention** | 25 checks, 20 `would` lines, a `$HOME` snapshot test to catch misses | Guaranteed by construction (see above) |
| **gum bootstrap and version drift** | `ensure_gum` + `gum_release` (~60 lines): Homebrew, GitHub release, `go install` fallback, installing curl/tar/gzip first. gum can be any version (the `--label-delimiter` workaround) | One artifact, with UI library versions pinned in `go.sum` |
| **Stringly-typed UI** | Dispatch on label text; first-word parsing of picker lines; tests coupled to label wording | Typed items; labels can change freely |
| **Parsing in Bash** | `names.txt` columns, `/etc/os-release`, `/proc/mounts`, three checksum formats, yq's `checksums_hashes_order`, xdg-ninja JSON via `jq` | `bufio`, `encoding/json`, `crypto/sha256`, `archive/tar`, `net/http`. The XDG feature no longer needs `jq`, and built-in downloads no longer need curl/wget/tar/gzip on minimal images |
| **Output is a wall of text** | `gum style` lines interleaved with raw apt/installer output | Per-step viewports, a summary and a log file |
| **No unit tests** | Only end-to-end harnesses; behaviour checked by sourcing functions by hand (AGENTS.md "Testing") | `go test` with coverage; e2e kept for flows |

Not solved:

- The `shell/` portability work (BSD vs GNU `column`, bash vs zsh), because that code
  stays shell.
- Distro quirks in package managers, which move to Go but don't disappear.
- `config.sh` being bash.

## Concerns and risks

| # | Concern | Severity | Mitigation |
| --- | --- | --- | --- |
| 1 | **Regression of hard-won distro fixes.** About 30 PRs of edge cases live in `lib/common.sh` and the installers | High | Port function by function with a table test per fix, citing the original PR. Run `tests/distros/run.sh` and `tests/macos.sh` before and after each phase, and diff their reports |
| 2 | **Second rewrite in about three weeks.** Churn for users, and feature work stops for 5–8 weeks | High | Phased migration behind `./setup.sh`; each phase ships independently and is releasable |
| 3 | **Terminal ownership:** sudo, chsh, installers and editors need the TTY | High | `ExecProcess` + `sudo -v` keep-alive, PTY capture, non-interactive flags (see above). Alpine's `doas` loses live progress |
| 4 | **Distribution and release pipeline:** binaries per OS/arch, attestations, edge builds for `main`, keeping the token away from the toolchain | High | Separate read-only build job; plain `go build` matrix; `tests/release.sh` coverage |
| 5 | **Bilingual repo:** Go + Bash, two sets of standards, contributors need both | Medium | Keep the Bash surface small and stable (`shell/`, `install.sh`, the `lib/common.sh` helper API). Extend AGENTS.md with a Go section |
| 6 | **Less hackable.** Today anyone can read or patch the menu in a shell they already know; a compiled binary is opaque | Medium | Keep `config.sh`, user installers and `shell/` as the extension points (they already are). Document `go run ./cmd/envsetup` for development |
| 7 | **Bubble Tea v2 is eight months old**, with an import-path change; ecosystem examples are mostly v1 | Medium | Pin versions; Dependabot `gomod`; stick to core Bubbles components |
| 8 | **More code in a sudo-adjacent tool.** The binary doesn't run as root, but it decides what does | Medium | Same model as today (`as_root` per command); never handle passwords; no new network endpoints; attestations |
| 9 | **Full-screen UIs are worse for screen readers and dumb terminals** than line prompts | Medium | Inline rendering by default; `--plain` mode that uses line prompts (shared with headless); honour `NO_COLOR` / `TERM=dumb` |
| 10 | **`$ENVSETUP_ROOT` moves** if assets are embedded and extracted | Medium | Keep the clone in Phase 0–3; decide on embedding separately, as an explicit `!` change with in-place rc migration |
| 11 | **`ENVSETUP_VERSION=<branch/commit>`** has no binary | Medium | Edge builds + `go build` fallback |
| 12 | **Testing the TUI end to end** is harder than faking gum | Medium | `teatest` for models, headless for flows, one PTY smoke check |
| 13 | **Binary size and download** on slow links (about 8–12 MB) | Low | About the same as gum's download, which it replaces |

## Lift

### Size

| | Today (Bash) | After (estimate) |
| --- | --- | --- |
| Product code moved | ~1,100 lines (`setup.sh` + `lib/` + Bash parts of `install.sh`) | 2,500–3,500 lines Go logic + 1,000–1,500 lines TUI |
| Shell that stays | `shell/` 482, installers 224, `install.sh` ~120, `lib/common.sh` ~120 slimmed, `setup.sh` shim ~20 | same |
| Tests | 1,445 lines of harnesses | 1,500–2,500 lines `go test`; harnesses reworked (~50% of smoke/macos/distros) |
| CI | 3 jobs + release | + `go vet`/lint/test, build matrix job, release asset upload, edge builds |
| Docs | README, AGENTS.md, `--help` | README install/architecture/testing sections, AGENTS.md Go standards, this ADR's follow-ups |

### Phases

Every phase is a releasable PR, or a small stack of PRs, that keeps `./setup.sh`,
`--dry-run`, `--uninstall` and the README's flows working.

| Phase | Deliverable | User-visible | Effort |
| --- | --- | --- | --- |
| **0. Pipeline** | Go module; `envsetup version`; CI (vet, lint, test); read-only build job; release uploads binaries + checksums + attestations; edge builds for `main`; `install.sh` downloads and verifies the binary but still runs Bash `setup.sh` | No (`ci`/`build` commits) | 3–5 days |
| **1. Core, read-only** | `platform`, `config` (option A), `pkgs` name mapping, `plan` types; `envsetup plan --json` for every step; parity check in smoke: Go plan vs Bash dry-run output for each profile/mode | No | 4–6 days |
| **2. Apply, headless** | `runner` (sudo keep-alive, PTY, logs), all steps' `Apply`, uninstall incl. logs; `envsetup apply --yes`; distros/macOS harnesses switched to headless and compared against the Bash reports | New `apply` command (`feat`) | 6–10 days |
| **3. TUI** | Bubble Tea app: menu, pickers, plan review, progress, prompts, `ExecProcess` for editor/chsh; `teatest` suite; `setup.sh` becomes a shim that execs the binary | Yes: new UI (`feat!`: different keys and screens) | 6–10 days |
| **4. Remove Bash core** | Delete gum bootstrap and `lib/*.sh` except the slim `lib/common.sh`; drop the bash-4 re-exec and Homebrew-bash prerequisite; update README/AGENTS.md | Yes (`feat!` if any flag or behaviour changes) | 3–6 days |
| | | **Total** | **22–37 days** |

The ranges assume one person fluent in Go who already knows this repo. Add about 30% for
someone learning Bubble Tea v2's Elm-style model at the same time. Phases 0–2 have value
on their own (headless mode, unit tests, construction-safe dry-run) even if Phase 3 never
ships.

## Alternatives considered

### A. Status quo

Zero cost. Keeps every problem in [Problems this would solve](#problems-this-would-solve).
That's a reasonable choice for a personal tool at v0.1.0 whose current pain is mostly
contributor-facing (the `set -e` and bash-3.2 rules), not user-facing.

### B. Stay on Bash and use more of gum

gum already has components the repo doesn't use:

| gum feature | Gain |
| --- | --- |
| `gum spin --show-output` | spinner per long step |
| `gum choose --no-limit` | pick which packages/installers/XDG moves to apply this run |
| `gum filter` | searchable extras / xdg-ninja catalogue |
| `gum table` | status dashboard, XDG plan |
| `gum pager` | diff preview, step logs |
| `gum log` | levelled, timestamped status lines instead of ad hoc colors |
| `gum format` | markdown help screens |

Add a `--yes` headless path, which would also simplify the tests, and per-run log files.
That's about 3–6 days and gets maybe a third of the user-visible gains. It doesn't fix
the structural problems: `set -e`, bash 4, string dispatch and convention-based dry-run.

### C. Hybrid: Go TUI front end over the Bash steps

A small Bubble Tea binary renders a plan and progress that the Bash steps emit as JSON
lines on a side channel. This gets the UI gains with less porting. It is rejected as an
end state because it adds a protocol between two languages, and it keeps all the Bash
hazards while adding a binary to distribute. It could still be a stepping stone, but
Phases 1–2 above get there more directly.

### D. Full rewrite in Go with Bubble Tea and Bubbles (this proposal)

See above.

### E. Other stacks

- Rust + ratatui: similar trade-offs, a heavier toolchain, and leaves the Charm
  ecosystem that gum's look comes from.
- Python + Textual: needs a Python runtime on a bare machine, which defeats the
  bootstrap.

Neither beats Go here.

## Decision

**Proposed:** don't start a big-bang rewrite. Adopt the gum features listed in
[Alternative B](#b-stay-on-bash-and-use-more-of-gum) now. Accept the Go/Bubble Tea
direction only as the phased migration above, starting with Phase 0, and only if both
of these hold:

1. The maintainer wants live progress, plan review or headless mode enough to fund
   5–8 weeks with no other feature work.
2. The decisions in [Open questions](#open-questions) are made first, because each
   changes a user contract.

Revisit if any of these happen:

- A second contributor joins.
- Headless provisioning (cloud-init, CI images) becomes a real use case.
- Bash-side bugs from `set -e`, dry-run guards or 3.2 compatibility keep recurring.

## Consequences

If accepted:

- **Positive:**
  - Dry-run safety by construction, a headless mode and unit tests.
  - No bash-4 or gum bootstrap.
  - A UI that can show progress, plans and failures properly.
  - Pinned UI library versions.
- **Negative:**
  - A bilingual repo and a binary release pipeline.
  - More code in the release path.
  - Weeks of feature freeze.
  - A new UI that changes users' habits, so `feat!` and a minor bump on 0.x.
  - The test harnesses get rewritten at the same time as the code they test.
- **Neutral:** `shell/`, installers, `config.sh` and package lists are unchanged for
  users under config option A.

## Open questions

1. Config: option A (bash-evaluated, recommended) or B (data file, `!`)?
2. Keep the git checkout, or embed assets and move `$ENVSETUP_ROOT`?
3. Support `ENVSETUP_VERSION=<branch|commit>` via edge builds, Go fallback, or drop it?
4. Is linux/arm/v7 still a target? (gum's bootstrap supports it; `envsetup::arch` doesn't.)
5. Inline or alt-screen rendering by default?
6. Should built-in installers move into Go (parallel, checksum-verified, no curl/tar), or
   stay as reference examples of the script contract?

## References

- Bubble Tea releases and v2 upgrade guide: <https://github.com/charmbracelet/bubbletea/releases>
- Bubbles: <https://github.com/charmbracelet/bubbles>
- gum (built on the above): <https://github.com/charmbracelet/gum>
- Repo standards this ADR is measured against: `AGENTS.md`
- Current entry points: `install.sh`, `setup.sh`, `lib/*.sh`; test seams: `tests/smoke.sh`
  (gum stub), `tests/distros/scenarios.sh`, `tests/macos.sh`
