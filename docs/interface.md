# API

This page lists envsetup's API.
The API is the set of parts that users rely on.

## The rule

The API is everything that a user directly uses while using envsetup.
A change to the API that is not backwards compatible is a breaking change.
A breaking change needs a new major version.
From 1.0.0 on, a 1.x release never breaks a setup that an older 1.x release made.

[CONTRIBUTING.md](../CONTRIBUTING.md#breaking-changes) gives examples of breaking changes.

## Settings in `config.sh`

`envsetup::load_config` in `lib/config.sh` sets each default.
Then it runs the user's `config.sh`.
The name, the meaning and the default of each setting are part of the API.

| Setting | Default | What it means |
| --- | --- | --- |
| `ENVSETUP_PROFILE` | The profile from the menu: `home` or `work`. | The profile of this machine. `config.sh` reads it. |
| `ENVSETUP_MODE` | `full`. For `work`, the mode from the menu: `full` or `lite`. | The mode of this machine. `config.sh` reads it. |
| `ENVSETUP_PACKAGES` | `packages/common.txt` + `packages/<profile>.txt` | The packages that **Install packages** installs. |
| `ENVSETUP_GIT_CONFIG` | `git/gitconfig`, as `key=value`. | The git settings that **Configure git** writes. Later entries win. |
| `ENVSETUP_INSTALLER_DIRS` | `installers/common` + `installers/<profile>` | The folders of scripts that **Run installers** runs. |
| `ENVSETUP_EXTRAS` | Empty. | The tools from `installers/extras/` that **Run installers** also installs. |
| `ENVSETUP_SKIP` | Empty. | The packages and installers to skip. |
| `ENVSETUP_SHELL` | `bash` | The value `zsh` also sets up zsh + oh-my-zsh. |
| `ENVSETUP_XDG_NINJA` | `0` | The value `1` adds **Move dotfiles to XDG dirs** to **Run everything**. |
| `ENVSETUP_REPO_URL` | `https://github.com/hunterdw0007/envsetup.git` | The repo that the `envsetup` command downloads from. |

## The `install.sh` command

The command and its URL are part of the API:

```sh
curl -fsSL https://raw.githubusercontent.com/hunterdw0007/envsetup/main/install.sh | bash
```

These variables change what the command does:

| Variable | What it does |
| --- | --- |
| `ENVSETUP_VERSION` | Selects a release, a branch or a commit. |
| `ENVSETUP_REPO_URL` | Sets the repo URL. |
| `ENVSETUP_CONFIG_REPO` | Gets `config.sh` from the user's own git repo. |

The command passes its options to `setup.sh`, for example `bash -s -- --dry-run`.

## Options of `setup.sh`

`./setup.sh --help` prints these options:

| Option | What it does |
| --- | --- |
| `-n`, `--dry-run` | Opens the menu, but changes nothing. |
| `--config <file>` | Adds the file's text to the end of `config.sh`, then opens the menu. |
| `--uninstall` | Removes what envsetup added. |
| `--status` | Checks what envsetup set up, and changes nothing. Exits 1 if any part is missing. |
| `--version` | Shows the release. |
| `-h`, `--help` | Shows the help. |

## The `envsetup` command

New shells get an `envsetup` command.
Its commands are part of the API:
`envsetup`, `update`, `status`, `config`, `uninstall`, `version`, `help` and `--help`.
It also passes other options to `setup.sh`.
[docs/shell.md](shell.md#the-envsetup-command) explains each command.

## Menu actions

The names of these menu actions are part of the API:

- **Select profile**
- **Paste config**
- **Edit config**
- **Link shell config**
- **Set up zsh + oh-my-zsh**
- **Configure git**
- **Set up SSH key**
- **Install packages**
- **Run installers**
- **Move dotfiles to XDG dirs**
- **Preview everything**
- **Run everything**
- **Check status**
- **Uninstall**
- **Quit**

The actions that **Run everything** runs, and their order, are part of the API too.
The [README](../README.md#use-the-menu) explains each action.

## Shell config

The aliases, functions and environment variables in `shell/` are part of the API.
So is the `PS1` prompt.
[docs/shell.md](shell.md) lists all of them.
It also lists the [git settings](shell.md#git-settings), which are part of the API too.

## Profiles, packages and installers

The profiles `home` and `work` are part of the API.
So are the modes `full` and `lite` of `work`.
The packages and installers in each profile are part of the API too:

- `packages/common.txt` and `packages/<profile>.txt` list the packages.
- `installers/<profile>/` holds the installers.
- `installers/extras/` holds the tools that `ENVSETUP_EXTRAS` can name.

## File paths

These paths are part of the API:

| Path | What it holds |
| --- | --- |
| `~/.config/envsetup`, or `$XDG_CONFIG_HOME/envsetup` | The user's files, such as `config.sh` and `shell.d`. Its path is `$ENVSETUP_STATE`. |
| `~/.local/share/envsetup`, or `$XDG_DATA_HOME/envsetup` | The copy of `shell/` that new shells load, and its `version` file. |
| `~/.local/state/envsetup/installed`, or `$XDG_STATE_HOME/envsetup/installed` | The tools that envsetup installed. |

## Changes that are not breaking

These changes do not need a new major version:

- A new feature, option, setting, menu action or alias.
- A setting gets a new name, and `ENVSETUP_RENAMED` in `lib/config.sh` lists the old name.
  envsetup still reads the old name.
  It asks before it writes the new name into `config.sh`.
- A pinned tool moves to a new major version.
  The tool belongs to its vendor, not to envsetup's API.
- A distro release reaches the end of its vendor's standard support ([#120](https://github.com/hunterdw0007/envsetup/issues/120)).
