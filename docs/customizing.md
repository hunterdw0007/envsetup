# Customize envsetup

The [README](../README.md#customize) explains `config.sh` and lists its settings.
This page adds details.

## Where config.sh lives

`config.sh` is at `~/.config/envsetup/config.sh`.
If you set `XDG_CONFIG_HOME`, it is at `$XDG_CONFIG_HOME/envsetup/config.sh`.
If `~/.config/envsetup` already exists, envsetup keeps using that folder.

**Link shell config** writes the folder's path into your startup files.
So every shell uses the same folder, even a shell without `XDG_CONFIG_HOME`.

## Use config.sh on other machines

Keep `config.sh` in your own dotfiles repo.
On a new machine, create a symlink to it at the path above.
Then run the curl command from the [README](../README.md#install).

## Popular packages

Most distros' package managers have the tools that people add.
Add these with `ENVSETUP_PACKAGES+=(...)`.
Use the Debian or Ubuntu name.
`packages/names.txt` translates the name for other package managers.

| Use | Packages |
| --- | --- |
| General | `fd-find` (fd), `zoxide`, `btop`, `git-delta`, `ncdu`, `tree` |
| Development | `golang-go`, `build-essential`, `python3-venv`, `pipx`, `make`, `podman` |
| Work | `ansible`, `kubectx` (Fedora and RHEL do not have it) |

Older LTS releases can miss the newest packages.
For example, Ubuntu 22.04 does not have `git-delta`.
**Install packages** lists each package that it could not install.

## Extras

Ubuntu LTS and Fedora do not have the tools below.
envsetup downloads them from each project's own releases.
It checks each download against a pinned sha256 checksum.
It gets the amd64 or arm64 build that matches the machine.
Add these tools with `ENVSETUP_EXTRAS`.

| `ENVSETUP_EXTRAS` | What it is |
| --- | --- |
| `starship` | A prompt for any shell. To use it, add `eval "$(starship init bash)"` to `config.sh`. |
| `lazygit` | A terminal app for git. |
| `k9s` | A terminal app for Kubernetes. |
| `yq` | mikefarah's YAML and JSON processor. Debian's `yq` is a different tool. |
| `mise` | Sets the runtime version for each project, for example node, python or go. New shells load it. |
| `uv` | A Python package and project manager. It includes `uvx`. |

## Your own installers

You can keep your own installer scripts in a folder outside this repo.
Add that folder to `ENVSETUP_INSTALLER_DIRS` in `config.sh`.
[CONTRIBUTING.md](../CONTRIBUTING.md#add-an-installer) explains how to write an installer.
