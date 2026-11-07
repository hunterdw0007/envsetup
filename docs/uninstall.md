# Uninstall

The [README](../README.md#uninstall) shows the uninstall commands.
This page lists what uninstall removes, what it asks about and what it keeps.

## What uninstall removes

Uninstall removes everything that envsetup added:

- envsetup's block in `~/.bashrc` and `~/.zshrc`
- the copy of `shell/` in `~/.local/share/envsetup`, and its `version` file
- the include line in `~/.gitconfig` and the file it includes
- your saved profile and mode
- the dotfile moves to XDG folders
- the git settings that sign your commits with the SSH key that envsetup created

Uninstall does not change the rest of each startup file.
Uninstall moves each dotfile back to its old path.
Sometimes a program creates the old path again.
Then uninstall leaves that dotfile in its new path and tells you why.
After you fix the problem, run uninstall again.

## What uninstall asks about

Uninstall asks before it removes your `config.sh`.
If you set `ENVSETUP_CONFIG_REPO`, uninstall asks "Keep ~/.config/envsetup/repo?".
The default answer keeps it.
If you delete the repo but keep `config.sh`, uninstall keeps a copy of the repo's `config.sh`.
Uninstall keeps `config.sh.bak`, your old `config.sh`, and lists it at the end.
Uninstall removes an empty `shell.d` folder.
If `shell.d` has files, uninstall asks "Keep ~/.config/envsetup/shell.d?".
The default answer keeps it.
If envsetup created `~/.ssh/id_ed25519`, uninstall asks "Keep ~/.ssh/id_ed25519?".
The default answer keeps it.
If envsetup changed your login shell to zsh, uninstall asks to change it back to bash.

## What uninstall keeps

Uninstall keeps these things, because they can exist without envsetup:

- packages and tools
- your git `user.name` and `user.email`
- oh-my-zsh, which has its own `uninstall_oh_my_zsh` command

At the end, uninstall lists what it kept.
