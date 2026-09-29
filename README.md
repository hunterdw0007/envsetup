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

## Manual install

```sh
git clone git@github.com:hunterdw0007/envsetup.git ~/envsetup
cd ~/envsetup
./setup.sh
```

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
- install the packages listed for `common` + the active profile (skipped for `work` lite)
- run the installer scripts under `installers/common` + the active profile — anything that
  isn't a plain package-manager package: vendor installers, manual binary downloads, or any
  other custom setup step (also skipped for `work` lite)

"Run everything" does all four in one shot; each is also available individually from the
menu if you just want to re-run one piece.

The `home` profile assumes the machine is yours to configure fully: linking installs zsh
and [oh-my-zsh](https://ohmyz.sh) if they're missing, offers to make zsh your login shell,
and then wires `shell/init.sh` into `~/.zshrc`. The `work` profile stays on bash and wires
`shell/init.sh` into `~/.bashrc`. Either default can be flipped with `ENVSETUP_SHELL`.

`setup.sh` will try to install `gum` itself (via `brew` or `go install`) if it isn't found.

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
ENVSETUP_SHELL=bash                                # stay on bash on the home profile
ENVSETUP_INSTALLER_DIRS+=("$HOME/dotfiles/envsetup-installers")
ENVSETUP_GIT_CONFIG+=("user.email=me@example.com" "alias.sw=switch")
[[ $ENVSETUP_PROFILE == work ]] && ENVSETUP_PACKAGES+=(kubectx)

alias k=kubectl                                    # anything else is ordinary shell config
```

| Setting | Default | Applied |
| --- | --- | --- |
| `ENVSETUP_PACKAGES` | `packages/common.txt` + `packages/<profile>.txt` | Install packages |
| `ENVSETUP_INSTALLER_DIRS` | `installers/common` + `installers/<profile>` | Run installers |
| `ENVSETUP_SKIP` | empty — names of packages/installers to leave out | Install packages, Run installers |
| `ENVSETUP_SHELL` | `zsh` on home, `bash` otherwise | Link shell config |
| `ENVSETUP_GIT_CONFIG` | `git/gitconfig`, as `key=value` (later entries win) | Configure git |
| aliases, exports, functions, `PS1` | `shell/` | every new shell, after the defaults |

Shell settings take effect in the next new shell. The `ENVSETUP_*` settings take effect the
next time you run the matching menu action (or "Run everything"). To carry your setup to
another machine, keep `config.sh` in your own dotfiles and symlink it into place before
running `install.sh`.

## Layout

```
install.sh           # curl | bash entry point: clones/updates the repo, then runs setup.sh
setup.sh             # gum TUI: profile/mode selection, linking, package installs
config.example.sh    # template for your ~/.config/envsetup/config.sh overrides
shell/
  shared/            # ps1, aliases, exports, functions loaded on every machine
                      # (work/lite only loads ps1 + aliases)
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

Package names are passed straight to whichever of `apt`/`dnf`/`brew`/`pacman` is detected on
the machine. To change what's installed or loaded for yourself, use `config.sh` (above)
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
