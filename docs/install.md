# Install and update

The top of the [README](../README.md) shows the install command.
This page explains what the command does and the other ways to install.

## What the command does

envsetup needs `bash`, `curl` and `git` on the machine.
On a machine without `git`, the command shows how to install `git`.
Then it stops.

The command does three things:

1. It downloads the newest release into a temporary folder.
2. It opens the menu.
3. When you quit the menu, it deletes the temporary folder.
   It also deletes the folder after an error or Ctrl-C.

**Link shell config** copies the shell config (`shell/`) to `~/.local/share/envsetup`.
If you set `XDG_DATA_HOME`, it copies the shell config to `$XDG_DATA_HOME/envsetup` instead.
New shells load it from there.
It also records the release there, in a file called `version`.
So envsetup itself does not stay on the machine.
Only your shell config, `config.sh` and the files that envsetup made stay.

## Update

To update to the newest release, run the same command again.
Or run `envsetup` in a new shell, which runs the same command for you.
[docs/shell.md](shell.md#the-envsetup-command) lists its other commands.
**Link shell config** (or **Run everything**) then replaces the copy.
Running the same release again changes nothing.

From 1.0.0 on, envsetup follows [Semantic Versioning](https://semver.org/).
Only a new major version, such as 2.0.0, can break something you use.
[docs/interface.md](interface.md) lists what that promise covers.
The changelog lists those changes first, under "Breaking changes".

## Select a release

Each release has a number, for example `v0.2.0`.
[`CHANGELOG.md`](../CHANGELOG.md) lists the changes in each release.
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

## Update from a `~/envsetup` folder

Before version 0.3.0, the command kept a copy of this repo in `~/envsetup`, or in `ENVSETUP_DIR`.
Your startup files loaded the shell config from that copy.
`ENVSETUP_DIR` no longer does anything.
To update, run the curl command from the README, not `~/envsetup/install.sh`.
**Link shell config** then rewrites envsetup's block in your startup files to load the new copy.
It also asks "Keep ~/envsetup?".
If you made changes in that folder, answer yes.
Then move your changes to `config.sh` (see [Customize](../README.md#customize)).

## Try it without changes

```sh
./setup.sh --dry-run
# or with curl, which deletes its download afterwards, as usual
curl -fsSL https://raw.githubusercontent.com/hunterdw0007/envsetup/main/install.sh | bash -s -- --dry-run
```

A dry run opens the real menu.
Each action then describes its changes but does not make them.
You can still select profiles and edit `config.sh`.
envsetup forgets those changes when you quit.
A dry run still loads `config.sh` to read its settings.
So the shell code that you edit in a dry run runs.
A dry run of **Paste config** checks only the syntax of the text.
It does not run the text.
It saves the text nowhere, not even for the session.
With `--dry-run`, `--config <file>` also checks only the syntax of the file.

The menu needs gum.
If the machine does not have gum, the dry run asks before it installs gum.
A dry run makes no other change.
gum's download needs curl, tar and gzip.
If one of them is missing, the dry run names it and stops.
Install the missing tools first.
Then start the dry run again.

The **Preview everything** action is the same as a dry run of **Run everything**.

## Install without curl

```sh
git clone git@github.com:hunterdw0007/envsetup.git ~/envsetup
cd ~/envsetup
./setup.sh
```

This method uses the newest commit on `main`.
To use a release, run `git checkout v0.2.0` first.
`git tag` lists the releases.
envsetup never deletes this folder.
New shells load the copy of `shell/` that **Link shell config** makes.
So run **Link shell config** again after you change `shell/`.
