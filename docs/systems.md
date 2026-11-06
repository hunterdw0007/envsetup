# Supported systems

The [README](../README.md#supported-systems) lists the supported systems and their package managers.
This page explains the details.

## Linux only

envsetup supports Linux only, including WSL.
On macOS, `install.sh` stops and changes nothing.
It names v0.3.0, the last release that supports macOS.
It also shows how to install v0.3.0 and how to uninstall envsetup.

## Package managers

envsetup uses the package manager that the machine has.
If the machine has Homebrew, envsetup uses Homebrew.
`packages/names.txt` translates package names for each package manager.

## EPEL

On RHEL and similar systems, about 15 packages come from EPEL.
These packages include fzf, ripgrep, bat, htop and neovim.
EPEL 9 does not have direnv.
Docker comes from Docker CE's own package repo.

Amazon Linux 2023 has no EPEL.
On Amazon Linux, envsetup cannot install fzf, ripgrep, bat and some other packages.
Add them to `ENVSETUP_SKIP` in `config.sh`.

## Root access and downloads

envsetup runs root steps with `sudo`, or with `doas` if the machine has it.
If you are already root, envsetup runs those steps directly.
The menu itself does not need sudo.
envsetup installs gum with Homebrew if the machine has it.
Otherwise it downloads gum's pinned release into `~/.local/bin` and checks its checksum.
If that fails and the machine has Go, it uses `go install`.
Installers download the amd64 or arm64 build that matches the machine.

`installers/versions.txt` sets the version and sha256 checksum of each download.
So two machines on the same release get the same tool versions.
A project may change a download after its release.
Then the download fails the checksum, and envsetup does not install it.
envsetup records each tool that it installs in `~/.local/state/envsetup/installed`.
If you set `XDG_STATE_HOME`, the file is `$XDG_STATE_HOME/envsetup/installed`.
A new release may pin a newer version of such a tool.
Then **Run installers** updates the tool and lists each update first.
Older releases kept no record.
So envsetup does not update a tool that an older release installed.
It treats that tool as one that you installed.
To use another version of a tool, install the tool yourself.
Installers skip any tool on your `PATH` that envsetup did not install.
