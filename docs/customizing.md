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

Keep `config.sh` at the top of your own git repo.
On a new machine, set `ENVSETUP_CONFIG_REPO` in the curl command from the [README](../README.md#install):

```sh
curl -fsSL https://raw.githubusercontent.com/hunterdw0007/envsetup/main/install.sh | ENVSETUP_CONFIG_REPO=github.com/me/dotfiles bash
```

- `ENVSETUP_CONFIG_REPO=me` is short for `github.com/me/envsetup-config`.
- `ENVSETUP_CONFIG_REPO=me/dotfiles` is short for `github.com/me/dotfiles`.
- A local repo needs an absolute path, such as `/srv/dotfiles`.
- A URL without a scheme uses https.
  An SSH URL such as `git@github.com:me/dotfiles.git` works too.
- envsetup clones the repo into `~/.config/envsetup/repo` before the menu opens.
- Then `config.sh` becomes a symlink to the `config.sh` in the repo.
- You may already have a `config.sh`.
  Then envsetup asks "Keep …?" first.
  The default answer keeps your file.
  If you answer no, envsetup moves your file to `config.sh.bak`.
  If you keep your file, later runs do not ask to pull.
- Each later run asks to pull the repo before the menu opens.
  Later runs do not need `ENVSETUP_CONFIG_REPO`.
- Your `config.sh` then lives in the clone.
  Commit and push your edits there.
  Otherwise a later pull can fail.
- A failed clone or pull shows a warning.
  The menu still opens.
- A dry run only describes the clone and the link.
  A dry-run edit changes a copy of `config.sh`, not the clone.

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
