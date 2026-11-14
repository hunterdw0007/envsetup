<div align="center">

# envsetup

**Set up your Linux shell in one command.**

[![Release](https://img.shields.io/github/v/release/hunterdw0007/envsetup)](https://github.com/hunterdw0007/envsetup/releases/latest) [![CI](https://img.shields.io/github/actions/workflow/status/hunterdw0007/envsetup/ci.yml?branch=main&label=CI)](https://github.com/hunterdw0007/envsetup/actions/workflows/ci.yml) [![License](https://img.shields.io/github/license/hunterdw0007/envsetup)](LICENSE)

</div>

```sh
curl -fsSL https://raw.githubusercontent.com/hunterdw0007/envsetup/main/install.sh | bash
```

![A dry run from a clone of envsetup selects the home profile, then runs Preview everything](docs/tapes/demo.gif)

envsetup sets up the shell on a new or wiped Linux machine.
It adds aliases, environment variables, shell functions and common command-line tools.
You choose what it does from a menu in the terminal.
The menu uses [gum](https://github.com/charmbracelet/gum).

## Highlights

- You choose each action from a menu. Nothing changes until you select an action.
- The `work` and `home` profiles fit different machines. The `lite` mode needs no sudo.
- A dry run (`--dry-run` or **Preview everything**) shows each change and makes none.
- **Uninstall** removes what envsetup added, except packages and tools.
- Installers pin the version of each release that they download. They check each file before they use it. You can also pin a release.
- Your own changes live in `~/.config/envsetup`. Updates never change them.

## Install

envsetup needs `bash`, `curl` and `git` on the machine.
Run the command at the top of this page, then:

1. Select **Select profile**, then `work` or `home`.
   For `work`, also select `full` or `lite`.
2. Select **Preview everything** to see the changes.
3. Select **Run everything** to make them.

The command deletes its download when you quit.
Only your shell config, `config.sh` and the files that envsetup made stay.
To update, run the command again, or run `envsetup` in a new shell.
Only a new major version, such as 2.0.0, can break something you use ([docs/interface.md](docs/interface.md)).
envsetup runs its root steps with `sudo` or `doas`.

These variables change what the command does:

| Variable | What it does |
| --- | --- |
| `ENVSETUP_REPO_URL` | Sets the repo URL, for example an SSH URL. |
| `ENVSETUP_VERSION` | Selects a release. See [Select a release](docs/install.md#select-a-release). |
| `ENVSETUP_CONFIG_REPO` | Gets `config.sh` from your own git repo. See [Use config.sh on other machines](docs/customizing.md#use-configsh-on-other-machines). |

[docs/install.md](docs/install.md) explains updates, releases, dry runs and an install without curl.

## Use the menu

envsetup changes nothing until you select an action.
Run `./setup.sh --help` to see an overview without the menu.
`--help` works on a machine without gum.

First, select a profile: `work` or `home`.
For `work`, also select a mode:

- `full` is for machines where you have sudo.
  It runs every action.
- `lite` is for machines without sudo.
  It installs nothing.

This README calls the `work` profile in `lite` mode "work lite".
Each profile and mode in the menu shows what it does on this machine.
For example, `work` shows how many packages it installs and which installers it runs.

**Run everything** runs these actions in order:

1. **Link shell config** loads envsetup from your shell startup file, for example `~/.bashrc`.
2. **Configure git** writes envsetup's git settings and asks for your name and email.
3. **Install packages** installs the packages for your profile.
4. **Run installers** runs scripts for tools that package managers do not have.
5. **Set up SSH key** creates `~/.ssh/id_ed25519` if it does not exist. See [docs/ssh.md](docs/ssh.md).
6. **Move dotfiles to XDG dirs**, only if you set `ENVSETUP_XDG_NINJA=1`.

With `ENVSETUP_SHELL=zsh`, **Link shell config** also runs **Set up zsh + oh-my-zsh**.
If one action fails, **Run everything** continues with the next action.
You can also run each action alone from the menu.
Work lite skips **Install packages** and **Run installers**.

<details>
<summary>The other menu actions</summary>

- **Select profile** changes the profile and mode.
- **Paste config** adds the text that you paste to the end of your `config.sh`.
  It can also save the text as a new file of your own shell code.
  See [Customize](#customize).
- **Edit config** opens your `config.sh` in an editor.
- **Set up zsh + oh-my-zsh** installs zsh and [oh-my-zsh](https://ohmyz.sh).
  It can also make zsh your login shell.
- **Move dotfiles to XDG dirs** moves dotfiles out of `$HOME`.
  See [docs/xdg.md](docs/xdg.md).
- **Preview everything** shows what **Run everything** would do.
- **Check status** checks what envsetup set up on this machine.
  It changes nothing.
  `./setup.sh --status` runs the same check without the menu or gum.
  Each line starts with "ok" or "missing".
  `--status` exits 1 if any line is "missing".
- **Uninstall** removes what envsetup added.
  See [Uninstall](#uninstall).

</details>

### What your shell gets

Every profile gets a prompt, aliases, shell functions and hooks for some tools.
Every profile except work lite also gets environment variables.
[docs/shell.md](docs/shell.md) lists all of them.

**Configure git** changes some of git's defaults.
For example, `git pull` rebases your commits and does not merge.
Also, `git aa` adds every file that `.gitignore` does not exclude, including `.env` files.
Read [the git settings](docs/shell.md#git-settings) before you run **Configure git**.

## Supported systems

envsetup supports Linux only, including WSL.
It uses the package manager that the machine has.
[docs/systems.md](docs/systems.md) explains macOS, EPEL, root access and downloads.

| System | Package manager | Notes |
|---|---|---|
| Ubuntu, Debian, Mint, Pop!_OS, WSL | `apt` | |
| Fedora | `dnf` | |
| RHEL, Rocky, Alma, CentOS Stream, Oracle Linux | `dnf` | Asks to turn on EPEL. On RHEL, turn on EPEL yourself. See [EPEL](docs/systems.md#epel). |
| Amazon Linux 2023 | `dnf` | Has no EPEL. See [EPEL](docs/systems.md#epel). |
| Arch, CachyOS, EndeavourOS, Manjaro | `pacman` | |
| openSUSE Tumbleweed and Leap | `zypper` | Leap 16.0 does not package `nmap`. For `work`, add it to `ENVSETUP_SKIP`. |
| Alpine | `apk` | Install bash first: `apk add bash curl`. |
| Bazzite, Aurora, Silverblue, SteamOS, Aeon | `brew` | `/usr` is read-only, so envsetup needs Homebrew or Nix. Bazzite and Aurora include Homebrew. |
| NixOS | `nix` | Installs into your user profile with `nix profile` or `nix-env`. |

envsetup supports each distro release until its security support ends.
[endoflife.date](https://endoflife.date) lists that date for each distro release.
Extended support does not count, paid or free.
Ubuntu Pro ESM and Debian LTS are two examples of extended support.
A rolling distro, such as Arch or openSUSE Tumbleweed, has no releases.
envsetup supports its current state.
For Fedora and Alpine, the tests use the newest release.
The image list in [`tests/distros/run.sh`](tests/distros/run.sh) names each distro release that the tests cover.
[CONTRIBUTING.md](CONTRIBUTING.md#goals) explains how a distro release leaves.

## Customize

The packages, installers, aliases and git settings in this repo are defaults.
To change a default, edit `~/.config/envsetup/config.sh`.
An update replaces the copy of `shell/`.
`config.sh` is outside that copy, so updates do not change it.

The fastest way is **Paste config** in the menu.
Paste your settings or shell code into the text box.
Save or cancel with the keys that gum shows under the box.
Then pick where the text goes:

- **settings** adds the text to the end of `config.sh`.
- **shell** saves the text as a new file in `~/.config/envsetup/shell.d`.
  **Paste config** asks for the file name.
  See [Your own shell files](docs/shell.md#your-own-shell-files).

<details>
<summary>How Paste config, Edit config and <code>--config</code> check your text</summary>

**Paste config** checks the text with `bash -n` first.
`bash -n` finds syntax errors without running the code.
If the text has an error, **Paste config** shows the line number and saves nothing.
It also saves nothing if the text is empty, or if the text runs `exit`.
Otherwise, it adds the text to the end of `config.sh`.
Then it shows each setting that changed, for example `Extras: +lazygit +k9s`.
A new shell file gets the same checks before **Paste config** saves it.
Each shell that loads the file runs the checks: bash for `.bash`, zsh for `.zsh`, and both for `.sh`.
Without zsh, **Paste config** cannot check a `.zsh` file, and it says so.
If a file with that name exists, **Paste config** asks "Replace <name>?".
The default answer keeps the old file.

`./setup.sh --config <file>` adds a file's text in the same way, then opens the menu.
On an error, it adds nothing and exits 1.
With curl, run `curl … | bash -s -- --config <file>`.

**Edit config** creates `config.sh` and opens it in `$EDITOR`.
Without `$EDITOR`, it uses `nano` if the machine has it, and `vi` otherwise.
The new `config.sh` is a copy of [`config.example.sh`](config.example.sh).
That copy lists every setting, all commented out.
After the editor closes, **Edit config** runs the same check and shows the changes.
`./setup.sh --edit-config` and `envsetup config` run **Edit config** without the menu.

</details>

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
| `ENVSETUP_REPO_URL` | `https://github.com/hunterdw0007/envsetup.git` | The `envsetup` command in your shell |
| aliases, environment variables, functions, `PS1` | `shell/` | Every new shell, after the defaults |
| your own shell files in `~/.config/envsetup/shell.d` | Empty. See [Your own shell files](docs/shell.md#your-own-shell-files). | Every new interactive shell, after `config.sh` |

A change to shell config takes effect in the next new shell.
A change to an `ENVSETUP_*` setting takes effect the next time you run its action.
[docs/customizing.md](docs/customizing.md) lists popular tools and explains where `config.sh` lives.

## Uninstall

```sh
curl -fsSL https://raw.githubusercontent.com/hunterdw0007/envsetup/main/install.sh | bash -s -- --uninstall
# shows what uninstall would remove
curl -fsSL https://raw.githubusercontent.com/hunterdw0007/envsetup/main/install.sh | bash -s -- --dry-run --uninstall
```

`envsetup uninstall` in a new shell does the same.
**Uninstall** in the menu and `./setup.sh --uninstall` in a clone also do the same.
Uninstall removes everything that envsetup added.
It asks before it removes anything that may be yours, such as `config.sh` or your SSH key.
It keeps packages and tools.
[docs/uninstall.md](docs/uninstall.md) lists each part.

## Related projects

- [gum](https://github.com/charmbracelet/gum) draws envsetup's menu.
- [VHS](https://github.com/charmbracelet/vhs) records the demo above.
- [oh-my-zsh](https://ohmyz.sh) is the zsh setup that **Set up zsh + oh-my-zsh** installs.
- [xdg-ninja](https://github.com/b3nj5m1n/xdg-ninja) tells **Move dotfiles to XDG dirs** which moves are safe.
- [thoughtbot/laptop](https://github.com/thoughtbot/laptop) is a similar setup script for macOS.

## More information

- [docs/install.md](docs/install.md): updates, releases, dry runs and an install without curl.
- [docs/shell.md](docs/shell.md): the prompt, aliases, functions and git settings.
- [docs/customizing.md](docs/customizing.md): popular tools and the location of `config.sh`.
- [docs/ssh.md](docs/ssh.md): the SSH key, GitHub and signed commits.
- [docs/xdg.md](docs/xdg.md): how envsetup moves dotfiles to XDG folders.
- [docs/systems.md](docs/systems.md): macOS, EPEL, root access and pinned downloads.
- [docs/uninstall.md](docs/uninstall.md): what uninstall removes, asks about and keeps.
- [docs/interface.md](docs/interface.md): the parts of envsetup that only a new major version may break.
- [CONTRIBUTING.md](CONTRIBUTING.md): the repo layout, new installers, releases and tests.

## License

MIT. See `LICENSE`.
To report a security problem, see [SECURITY.md](SECURITY.md).
