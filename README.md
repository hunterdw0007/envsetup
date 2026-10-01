# envsetup

A [gum](https://github.com/charmbracelet/gum)-powered TUI for getting a new or wiped machine
back to a working shell: aliases, exports, functions, and your usual CLI tools.

## Quick install

Once this repo is public, one line gets you from a bare machine into the setup menu:

```sh
curl -fsSL https://raw.githubusercontent.com/hunterdw0007/envsetup/main/install.sh | bash
```

`install.sh` installs `git` if it's missing, clones this repo into `~/envsetup` (or
`$ENVSETUP_DIR` if set), and hands off straight into `./setup.sh`. Running it again later
just fast-forwards the existing checkout instead of re-cloning. Point it at a different
remote (e.g. an SSH URL) with `ENVSETUP_REPO_URL`.

### Try it without changing anything

```sh
./setup.sh --dry-run
# or, straight from curl (this still clones the repo into ~/envsetup, nothing else):
curl -fsSL https://raw.githubusercontent.com/hunterdw0007/envsetup/main/install.sh | bash -s -- --dry-run
```

A dry run is the real menu, but every step says what it *would* do instead of doing it:
which rc file it would edit, whether it would switch your login shell, which packages it
would install and whether that needs sudo, which installers it would run. Profile picks
and "Edit config" still work, so you can try different setups, but they're forgotten when
you quit. The menu needs `gum`, so if it isn't installed yet the dry run asks before
installing it; that's the only change it can make. In a normal session, **Preview
everything** does the same for "Run everything".

### While the repo is private

`raw.githubusercontent.com` won't serve a private repo to an anonymous request, so until
this repo is made public, use one of these instead:

```sh
# authenticate the fetch with a token that can read this repo
curl -fsSL -H "Authorization: token $GITHUB_TOKEN" \
  https://raw.githubusercontent.com/hunterdw0007/envsetup/main/install.sh | bash

# or just clone over SSH and run it locally
git clone git@github.com:hunterdw0007/envsetup.git ~/envsetup && ~/envsetup/install.sh
```

## Supported systems

envsetup uses whichever package manager the machine has, and translates package names
for it (`packages/names.txt`). Homebrew wins when it's installed.

| System | Uses | Notes |
|---|---|---|
| Ubuntu, Debian, Mint, Pop!_OS, WSL | `apt` | |
| Fedora | `dnf` | |
| RHEL, Rocky, Alma, CentOS Stream, Oracle Linux | `dnf` | Asks to enable EPEL, where fzf, ripgrep, bat, htop, neovim and ~10 more come from |
| Amazon Linux 2023 | `dnf` | No EPEL, so several extras (fzf, ripgrep, bat, ...) are reported as not installable; `ENVSETUP_SKIP` them |
| Arch, CachyOS, EndeavourOS, Manjaro | `pacman` | |
| openSUSE Tumbleweed and Leap | `zypper` | |
| Alpine | `apk` | Needs bash first: `apk add bash curl` |
| Bazzite, Aurora, Silverblue, SteamOS, Aeon | `brew` | `/usr` is read-only, so it needs Homebrew (Bazzite and Aurora ship it), or else Nix |
| NixOS | `nix` | Installs into your user profile (`nix profile` or `nix-env`) |

Root steps go through `sudo`, or `doas` if that's what the machine has, or run directly
when you're already root (containers, a fresh WSL distro). `gum` comes from Homebrew if
you have it, else from its GitHub release into `~/.local/bin`, so no sudo is needed for
the menu itself. Installers download the amd64 or arm64 build to match the machine.

## Manual install

```sh
git clone git@github.com:hunterdw0007/envsetup.git ~/envsetup
cd ~/envsetup
./setup.sh
```

Nothing changes until you pick an action. `./setup.sh --help` gives an overview without
launching the menu (it works before `gum` is installed), and the profile and mode pickers
say what each choice does on *this* machine, e.g.
`work  bash · 23 packages · 5 installers (awscli, gh, helm, kubectl, terraform)`, worked
out from your `config.sh` if you have one.

From the menu you can:

- pick a machine profile (`work` or `home`)
- for `work`, also pick a mode: `full` assumes sudo access and does everything below;
  `lite` assumes no sudo access, so it only loads the prompt (`ps1.sh`) and aliases and
  skips package installs entirely
- edit your personal config (see [Customizing without forking](#customizing-without-forking))
- link `shell/init.sh` into your rc file, which loads shared config plus the active
  profile's overlay
- configure git: writes `git/gitconfig` plus your config's git entries to
  `~/.config/envsetup/gitconfig`, includes that from `~/.gitconfig`, and prompts for
  `user.name`/`user.email` if nothing set them. Runs regardless of profile/mode — it never
  needs sudo
- install the packages listed for `common` + the active profile (skipped for `work` lite);
  if one can't be installed, the rest still are, and it says which one failed
- run the installer scripts under `installers/common` + the active profile — anything that
  isn't a plain package-manager package: vendor installers, manual binary downloads, or any
  other custom setup step (also skipped for `work` lite)
- move dotfiles out of `$HOME` into XDG directories (optional, see
  [below](#moving-dotfiles-to-xdg-directories-optional))
- take it all back out again (see [Uninstalling](#uninstalling))

"Run everything" does all four in one shot, carrying on past a step that fails; each is
also available individually from the menu if you just want to re-run one piece.

Linking wires `shell/init.sh` into `~/.bashrc` on every profile. zsh is opt-in: **Set up
zsh + oh-my-zsh** in the menu installs zsh and [oh-my-zsh](https://ohmyz.sh) if they're
missing, offers to make zsh your login shell, and wires the same config into `~/.zshrc`.
`ENVSETUP_SHELL=zsh` in `config.sh` makes that part of "Link shell config" and "Run
everything".

`setup.sh` will try to install `gum` itself (via `brew` or `go install`) if it isn't found.

### What your shell gets

Every profile and mode gets the prompt and aliases. Work lite gets only those two;
everything else also gets the exports and functions.

- **Prompt** (bash): time, kube context, a collapsed path (`~/d/envsetup`), git branch and
  ahead/behind, then `❯` on its own line. In zsh, the oh-my-zsh theme owns the prompt
  instead.
- **Aliases**: `ls` in color, `la`, `ll`, `..`/`...`/`....`. `cat`/`less` go through `bat`
  when it's installed. On work there are also kubectl shortcuts (`kc`, `kcaMem`).
- **Exports**: XDG base directories, `EDITOR=vim`, and man pages through `bat`.
- **Functions** (bash): multi-repo git helpers for a directory of checkouts. They are
  `branchAll` (`ba`), `fetchAll` (`fa`), `pullMainAll` (`pma`), `mainOriginAll`,
  `pruneBranches` (`pb`) and `pruneBranchesAll` (`pba`); most take `--help`. On work
  there is also `resetNode` for helm charts.

Git shortcuts are git aliases (`git s`, `git d`, `git l`, ...) in `git/gitconfig`, not
shell aliases.

### Moving dotfiles to XDG directories (optional)

**Move dotfiles to XDG dirs** in the menu tidies `$HOME` using
[xdg-ninja](https://github.com/b3nj5m1n/xdg-ninja)'s notes on 600+ programs. It moves
files like `~/.docker` to `~/.config/docker` and exports whatever variable the program
needs (`DOCKER_CONFIG`) from every new shell. Set `ENVSETUP_XDG_NINJA=1` in `config.sh`
to make it part of "Run everything", so tools it installs get tidied too.

xdg-ninja's notes are written for people, so only the mechanical fixes are applied
automatically:

- one `export` and a move
- a move to a path the program already reads

Everything else is left in place and listed, with the reason:

- notes with a version caveat or extra steps
- dotfiles your rc files mention (e.g. `~/.cargo/env`)
- symlinks
- variables that are already set or shared (`HISTFILE`, `ZDOTDIR`, `GNUPGHOME`)
- the rc files themselves and `~/.gitconfig`

It shows the list and asks before moving anything, and `--dry-run` previews it. Every
move is recorded, so uninstall moves them all back. It needs `git` and `jq` (both in
`packages/common.txt`). The notes are cached in `~/.cache/envsetup/xdg-ninja`, from
`ENVSETUP_XDG_NINJA_URL` if you point that at a mirror.

The exports apply to shells that load envsetup. A program started some other way (a
desktop launcher, cron) won't see them.

## Customizing without forking

Everything shipped here (packages, installers, aliases, git settings) is a *default*. To
change any of it for yourself, put your changes in one file,
`~/.config/envsetup/config.sh`, instead of editing this repo. It lives outside the
checkout, so `git pull` and re-running `install.sh` never conflict with it — editing
tracked files, by contrast, makes the next update abort.

Pick **Edit config** in the menu to create it from [`config.example.sh`](config.example.sh)
(every option, all commented out) and open it in `$EDITOR`. It's plain bash, sourced
after the defaults, so `+=` extends a default, `=` replaces it, and you can branch on
`$ENVSETUP_PROFILE` / `$ENVSETUP_MODE` for per-machine tweaks:

```sh
ENVSETUP_PACKAGES+=(neovim)                        # add to the default package list
ENVSETUP_SKIP=(docker.io terraform)                # drop a default package or installer
ENVSETUP_SHELL=zsh                                 # also set up zsh + oh-my-zsh
ENVSETUP_INSTALLER_DIRS+=("$HOME/dotfiles/envsetup-installers")
ENVSETUP_GIT_CONFIG+=("user.email=me@example.com" "pull.rebase=false")
[[ $ENVSETUP_PROFILE == work ]] && ENVSETUP_PACKAGES+=(kubectx)

alias k=kubectl                                    # anything else is ordinary shell config
```

| Setting | Default | Applied |
| --- | --- | --- |
| `ENVSETUP_PACKAGES` | `packages/common.txt` + `packages/<profile>.txt` | Install packages |
| `ENVSETUP_INSTALLER_DIRS` | `installers/common` + `installers/<profile>` | Run installers |
| `ENVSETUP_SKIP` | empty — names of packages/installers to leave out | Install packages, Run installers |
| `ENVSETUP_SHELL` | `bash`; `zsh` also sets up zsh + oh-my-zsh | Link shell config |
| `ENVSETUP_GIT_CONFIG` | `git/gitconfig`, as `key=value` (later entries win) | Configure git |
| `ENVSETUP_XDG_NINJA` | `0`; `1` adds "Move dotfiles to XDG dirs" to "Run everything" | Run everything |
| aliases, exports, functions, `PS1` | `shell/` | every new shell, after the defaults |

Shell settings take effect in the next new shell. The `ENVSETUP_*` settings take effect the
next time you run the matching menu action (or "Run everything"). To carry your setup to
another machine, keep `config.sh` in your own dotfiles and symlink it into place before
running `install.sh`.

## Uninstalling

```sh
./setup.sh --uninstall            # or "Uninstall" in the menu
./setup.sh --dry-run --uninstall  # see what it would remove first
```

This takes out everything envsetup added: its block in `~/.bashrc`/`~/.zshrc` (the rest of
the file is left byte-for-byte as it was), its include in `~/.gitconfig` and the generated
file behind it, and its saved profile/mode. Dotfiles it moved to XDG directories go back
where they were. It asks before removing anything that might
be yours: your `config.sh`, and, if it set you up on zsh, switching your login shell back
to bash. Packages and tools stay, since they may have been there before
envsetup, as do your git `user.name`/`user.email` and oh-my-zsh (it has its own
`uninstall_oh_my_zsh`). It lists all of that at the end, along with how to delete the
checkout itself.

## Layout

```
install.sh           # curl | bash entry point: clones/updates the repo, then runs setup.sh
setup.sh             # gum TUI: profile/mode selection, linking, package installs
config.example.sh    # template for your ~/.config/envsetup/config.sh overrides
shell/
  shared/            # ps1, aliases, exports, functions loaded on every machine
                      # (work/lite only loads ps1 + aliases), plus colors.sh
                      # for the functions
  profiles/
    work/            # overlays loaded only when profile = work
    home/            # overlays loaded only when profile = home
  init.sh            # sourced from your rc file; wires the above together
packages/
  common.txt         # packages installed everywhere
  work.txt           # extra packages for the work profile
  home.txt           # extra packages for the home profile
installers/
  common/            # scripts run for every profile
  work/              # scripts run only for profile = work (full mode only)
  home/              # scripts run only for profile = home
git/
  gitconfig          # default git aliases/settings (no identity)
```

Package lists use Debian/Ubuntu's names; `packages/names.txt` maps the ones other package
managers call something else. To change what's installed or loaded for yourself, use `config.sh` (above)
rather than editing these files.

### Adding a third-party or custom installer

Some tools don't come from a package manager (`terraform`, `kubectl`, `awscli`, ...), and
sometimes you just want an arbitrary setup step to run (cloning a repo, writing a config
file, whatever). Either kind goes in `installers/`:

1. Drop a script in `installers/common/<name>.sh` (every profile) or
   `installers/<profile>/<name>.sh` (that profile only), e.g. `installers/work/terraform.sh`.
2. Make it idempotent — check whether the thing is already done and exit early if so, since
   "Run installers" may run again later. `installers/work/kubectl.sh` is a working example.
3. It runs as its own `bash` process, so source `$ENVSETUP_ROOT/lib/common.sh` yourself if you
   want helpers like `envsetup::has_cmd`.

To add your own installers without touching this repo, keep them in a directory of your own
and add it via `ENVSETUP_INSTALLER_DIRS` in `config.sh`.

Scripts run directory by directory, alphabetically within each. One failing script doesn't
stop the others — failures are collected and reported at the end.

## Contributing

See `AGENTS.md` for commit/branch conventions and code standards. CI
(`.github/workflows/ci.yml`) runs `bash -n` and `shellcheck` on every shell script for
every push and PR.
