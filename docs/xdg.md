# Move dotfiles to XDG folders

The **Move dotfiles to XDG dirs** action removes clutter from `$HOME`.
It uses [xdg-ninja](https://github.com/b3nj5m1n/xdg-ninja)'s notes on more than 600 programs.
For example, it moves `~/.docker` to `~/.config/docker`.
It then exports the variable that the program needs, here `DOCKER_CONFIG`.
Every new shell gets that variable.

To include this action in **Run everything**, set `ENVSETUP_XDG_NINJA=1` in `config.sh`.
Then the action also moves dotfiles from tools that **Run everything** installs.

## What it moves

xdg-ninja's notes are for people to read.
So envsetup moves a dotfile only in these two cases:

- The note asks for one `export` and one move.
- The note asks for a move to a path that the program already reads.

envsetup leaves these dotfiles in place:

- dotfiles whose notes mention a version or extra steps
- dotfiles that your startup files mention, for example `~/.cargo/env`
- symlinks
- dotfiles whose variable already has a value or that other programs share, for example `HISTFILE`, `ZDOTDIR` and `GNUPGHOME`
- the startup files and `~/.gitconfig`

envsetup lists each dotfile that it leaves in place, with the reason.

## How it moves them

The action shows the list of moves first.
It asks before it moves anything.
`--dry-run` shows the list without moving anything.

envsetup records every move.
So [uninstall](../README.md#uninstall) can move each dotfile back.

The action needs `git` and `jq`.
`packages/common.txt` includes both.

envsetup saves xdg-ninja's notes in `~/.cache/envsetup/xdg-ninja`.
To download the notes from a mirror, set `ENVSETUP_XDG_NINJA_URL`.

## Limits

Only shells that load envsetup get the new variables.
Programs that start another way do not get them.
Examples are a desktop launcher and cron.
