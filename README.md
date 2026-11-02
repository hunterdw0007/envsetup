# envsetup

envsetup sets up the shell on a new or wiped Linux machine.
It adds aliases, environment variables, shell functions and common command-line tools.
You choose what it does from a menu in the terminal.
The menu uses [gum](https://github.com/charmbracelet/gum).

## Install

Run this command on the machine:

```sh
curl -fsSL https://raw.githubusercontent.com/hunterdw0007/envsetup/main/install.sh | bash
```

The command does four things:

1. It installs `git` if the machine does not have it.
2. It downloads the newest release into a temporary folder.
3. It opens the menu.
4. When you quit the menu, it deletes the temporary folder, also after an error or Ctrl-C.

**Link shell config** copies the shell config (`shell/`) to `~/.local/share/envsetup`,
or to `$XDG_DATA_HOME/envsetup` if you set `XDG_DATA_HOME`.
New shells load it from there.
It also records the release there, in a file called `version`.
So envsetup does not stay on the machine: only your shell config, `config.sh` and the files that envsetup made stay.

To update to the newest release, run the same command again.
**Link shell config** (or **Run everything**) then replaces the copy.
Running the same release again changes nothing.

These variables change what the command does:

| Variable | What it does |
| --- | --- |
| `ENVSETUP_REPO_URL` | Sets the repo URL, for example an SSH URL. |
| `ENVSETUP_VERSION` | Selects a release. See [Select a release](#select-a-release). |

### Select a release

Each release has a number, for example `v0.2.0`.
[`CHANGELOG.md`](CHANGELOG.md) lists the changes in each release.
The [releases page](https://github.com/hunterdw0007/envsetup/releases) lists them too.
To install a specific release, set `ENVSETUP_VERSION`:

```sh
curl -fsSL https://raw.githubusercontent.com/hunterdw0007/envsetup/main/install.sh | ENVSETUP_VERSION=v0.2.0 bash
```

- `ENVSETUP_VERSION` also accepts `0.2.0`, a branch name or a commit.
- `ENVSETUP_VERSION=main` gives you changes that are not in a release yet.
- An unknown value shows the list of releases.
- A run without `ENVSETUP_VERSION` selects the newest release again.
- `~/.local/share/envsetup/version` shows the release your shells use.

### Update from a `~/envsetup` folder

Before version 0.3.0, the command kept a copy of this repo in `~/envsetup` (or in `ENVSETUP_DIR`), and your startup files loaded the shell config from it.
`ENVSETUP_DIR` no longer does anything.
To update, run the curl command above, not `~/envsetup/install.sh`.
**Link shell config** then rewrites envsetup's block in your startup files to load the copy, and asks "Keep ~/envsetup?".
If you made changes in that folder, answer yes and move them to `config.sh` (see [Customize](#customize)).

envsetup is still at version 0.x.
In 0.x, a release can change something you use every day.
The changelog lists these changes first, under "Breaking changes".

### Try it without changes

```sh
./setup.sh --dry-run
# or with curl (it deletes its download afterwards, as usual)
curl -fsSL https://raw.githubusercontent.com/hunterdw0007/envsetup/main/install.sh | bash -s -- --dry-run
```

A dry run opens the real menu.
Each action then describes its changes but does not make them.
You can still select profiles and edit `config.sh`.
envsetup forgets those changes when you quit.

The menu needs gum.
If the machine does not have gum, the dry run asks before it installs gum.
A dry run makes no other change.

The **Preview everything** action is the same as a dry run of **Run everything**.

### Install without curl

```sh
git clone git@github.com:hunterdw0007/envsetup.git ~/envsetup
cd ~/envsetup
./setup.sh
```

This method uses the newest commit on `main`.
To use a release, run `git checkout v0.2.0` first.
`git tag` lists the releases.
envsetup never deletes this folder.
New shells load the copy of `shell/` that **Link shell config** makes, so run it again after you change `shell/`.

## Use the menu

envsetup changes nothing until you select an action.
Run `./setup.sh --help` to see an overview without the menu.
`--help` works on a machine without gum.

First, select a profile: `work` or `home`.
For `work`, also select a mode:

- `full` is for machines where you have sudo. It runs every action.
- `lite` is for machines without sudo. It installs nothing.

This README calls the `work` profile in `lite` mode "work lite".

Each profile and mode in the menu shows what it does on this machine.
For example, `work` shows how many packages it installs and which installers it runs.

**Run everything** runs these actions in order:

1. **Link shell config** loads envsetup from your shell startup file, for example `~/.bashrc`.
2. **Configure git** writes envsetup's git settings and asks for your name and email.
3. **Install packages** installs the packages for your profile.
4. **Run installers** runs scripts for tools that package managers do not have.
5. **Move dotfiles to XDG dirs**, only if you set `ENVSETUP_XDG_NINJA=1`.

With `ENVSETUP_SHELL=zsh`, **Link shell config** also runs **Set up zsh + oh-my-zsh**.

If one action fails, **Run everything** continues with the next action.
You can also run each action alone from the menu.
Work lite skips **Install packages** and **Run installers**.

The menu has these other actions:

- **Select profile** changes the profile and mode.
- **Edit config** opens your `config.sh`. See [Customize](#customize).
- **Set up zsh + oh-my-zsh** installs zsh and [oh-my-zsh](https://ohmyz.sh). It can also make zsh your login shell.
- **Move dotfiles to XDG dirs** moves dotfiles out of `$HOME`. See [docs/xdg.md](docs/xdg.md).
- **Preview everything** shows what **Run everything** would do.
- **Uninstall** removes what envsetup added. See [Uninstall](#uninstall).

### What your shell gets

Every profile gets a prompt, aliases and hooks for some tools.
Every profile except work lite also gets environment variables and shell functions.
[docs/shell.md](docs/shell.md) lists all of them.

**Configure git** changes some of git's defaults.
For example, `git pull` rebases your commits and does not merge.
Also, `git aa` adds every file that `.gitignore` does not exclude, including `.env` files.
Read [the git settings](docs/shell.md#git-settings) before you run **Configure git**.

## Supported systems

envsetup supports Linux only, including WSL.
On macOS, `install.sh` stops and changes nothing.
It names v0.3.0, the last release that supports macOS, and shows how to install it.

envsetup uses the package manager that the machine has.
If the machine has Homebrew, envsetup uses Homebrew.
`packages/names.txt` translates package names for each package manager.

| System | Package manager | Notes |
|---|---|---|
| Ubuntu, Debian, Mint, Pop!_OS, WSL | `apt` | |
| Fedora | `dnf` | |
| RHEL, Rocky, Alma, CentOS Stream, Oracle Linux | `dnf` | Asks to turn on EPEL. See [EPEL](#epel). |
| Amazon Linux 2023 | `dnf` | Has no EPEL. See [EPEL](#epel). |
| Arch, CachyOS, EndeavourOS, Manjaro | `pacman` | |
| openSUSE Tumbleweed and Leap | `zypper` | |
| Alpine | `apk` | Install bash first: `apk add bash curl`. |
| Bazzite, Aurora, Silverblue, SteamOS, Aeon | `brew` | `/usr` is read-only, so envsetup needs Homebrew or Nix. Bazzite and Aurora include Homebrew. |
| NixOS | `nix` | Installs into your user profile with `nix profile` or `nix-env`. |

### EPEL

On RHEL and similar systems, about 15 packages come from EPEL.
These packages include fzf, ripgrep, bat, htop and neovim.
EPEL 9 does not have direnv.
Docker comes from Docker CE's own package repo.

Amazon Linux 2023 has no EPEL.
On Amazon Linux, envsetup cannot install fzf, ripgrep, bat and some other packages.
Add them to `ENVSETUP_SKIP` in `config.sh`.

### Root access and downloads

envsetup runs root steps with `sudo`, or with `doas` if the machine has it.
If you are already root, envsetup runs those steps directly.
The menu itself does not need sudo.
envsetup installs gum with Homebrew if the machine has it.
Otherwise it downloads gum's pinned, checksum-verified release into `~/.local/bin`.
If that fails and the machine has Go, it uses `go install`.
Installers download the amd64 or arm64 build that matches the machine.

`installers/versions.txt` sets the version and sha256 checksum of each download.
So two machines on the same release get the same tool versions.
A changed download from upstream fails the checksum, so envsetup does not install it.
To use a newer version of a tool, install the tool yourself.
Installers skip any tool that is already on your `PATH`.

## Customize

The packages, installers, aliases and git settings in this repo are defaults.
To change a default, edit `~/.config/envsetup/config.sh`.
envsetup does not keep a copy of this repo on your machine, and an update replaces the copy of `shell/`.
`config.sh` is outside both, so updates do not change it.

Select **Edit config** in the menu to create `config.sh` and open it in `$EDITOR`.
The new `config.sh` is a copy of [`config.example.sh`](config.example.sh).
That copy lists every setting, all commented out.

`config.sh` is a bash script.
envsetup runs it after it loads the defaults.

- `+=` adds to a default list.
- `=` replaces a default.
- `$ENVSETUP_PROFILE` and `$ENVSETUP_MODE` let you change settings for each machine.

```sh
ENVSETUP_PACKAGES+=(neovim)                        # add to the default package list
ENVSETUP_PACKAGES+=(fd-find zoxide btop git-delta) # any package, by its Debian name
ENVSETUP_EXTRAS=(lazygit k9s)                      # tools that distros do not package
ENVSETUP_SKIP=(docker terraform)                   # remove a default package or installer
ENVSETUP_SHELL=zsh                                 # also set up zsh + oh-my-zsh
ENVSETUP_INSTALLER_DIRS+=("$HOME/dotfiles/envsetup-installers")
ENVSETUP_GIT_CONFIG+=("user.email=me@example.com" "pull.rebase=false")
[[ $ENVSETUP_PROFILE == work ]] && ENVSETUP_PACKAGES+=(kubectx)

alias k=kubectl                                    # any other shell config works too
```

| Setting | Default | Used by |
| --- | --- | --- |
| `ENVSETUP_PACKAGES` | `packages/common.txt` + `packages/<profile>.txt` | Install packages |
| `ENVSETUP_INSTALLER_DIRS` | `installers/common` + `installers/<profile>` | Run installers |
| `ENVSETUP_EXTRAS` | Empty. Lists tools from `installers/extras/` to install. | Run installers |
| `ENVSETUP_SKIP` | Empty. Lists packages and installers to skip. | Install packages, Run installers |
| `ENVSETUP_SHELL` | `bash`. The value `zsh` also sets up zsh + oh-my-zsh. | Link shell config |
| `ENVSETUP_GIT_CONFIG` | `git/gitconfig`, as `key=value`. Later entries win. | Configure git |
| `ENVSETUP_XDG_NINJA` | `0`. The value `1` adds **Move dotfiles to XDG dirs** to **Run everything**. | Run everything |
| aliases, environment variables, functions, `PS1` | `shell/` | Every new shell, after the defaults |

A change to shell config takes effect in the next new shell.
A change to an `ENVSETUP_*` setting takes effect the next time you run its action.

[docs/customizing.md](docs/customizing.md) lists popular tools to add.
It also explains where `config.sh` lives and how to use it on other machines.

## Uninstall

```sh
curl -fsSL https://raw.githubusercontent.com/hunterdw0007/envsetup/main/install.sh | bash -s -- --uninstall
# shows what uninstall would remove
curl -fsSL https://raw.githubusercontent.com/hunterdw0007/envsetup/main/install.sh | bash -s -- --dry-run --uninstall
```

**Uninstall** in the menu does the same, and so does `./setup.sh --uninstall` in a clone.

Uninstall removes everything that envsetup added:

- envsetup's block in `~/.bashrc` and `~/.zshrc`
- the copy of `shell/` in `~/.local/share/envsetup`, and its `version` file
- the include line in `~/.gitconfig` and the file it includes
- your saved profile and mode
- the dotfile moves to XDG folders

Uninstall does not change the rest of each startup file.
Uninstall moves each dotfile back to its old path.
Sometimes a program creates the old path again.
Then uninstall leaves that dotfile in its new path and tells you why.
After you fix the problem, run uninstall again.

Uninstall asks before it removes your `config.sh`.
If envsetup changed your login shell to zsh, uninstall asks to change it back to bash.

Uninstall keeps these things, because they can exist without envsetup:

- packages and tools
- your git `user.name` and `user.email`
- oh-my-zsh, which has its own `uninstall_oh_my_zsh` command

At the end, uninstall lists what it kept.

## More information

- [docs/shell.md](docs/shell.md): the prompt, aliases, functions and git settings.
- [docs/customizing.md](docs/customizing.md): popular tools and the location of `config.sh`.
- [docs/xdg.md](docs/xdg.md): how envsetup moves dotfiles to XDG folders.
- [CONTRIBUTING.md](CONTRIBUTING.md): the repo layout, new installers, releases and tests.

## License

MIT. See `LICENSE`.
To report a security problem, see `SECURITY.md`.
