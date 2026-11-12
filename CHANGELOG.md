# Changelog

Every release of envsetup, newest first, with what changed in it. CI writes each entry
from the commits on `main` when it releases them (see "Releases" in AGENTS.md), so
don't edit this file by hand.

## v0.15.5 (2026-11-12)

### Fixes

- **installers**: bump pinned tool versions (#168)

## v0.15.4 (2026-11-12)

### Fixes

- install no system package in a dry run (#163)
- run no pasted text in a dry run of Paste config (#164)
- **installers**: drop the two unchecked root downloads (#166)

## v0.15.3 (2026-11-12)

### Fixes

- **shell**: make envsetup config run the checks of Edit config (#165)

## v0.15.2 (2026-11-12)

### Fixes

- **shell**: set EDITOR=vim only when vim exists (#161)

## v0.15.1 (2026-11-12)

### Fixes

- **work**: load the shell functions in work lite (#170)

## v0.15.0 (2026-11-07)

### Features

- **distros**: test openSUSE Leap 16.0 instead of Leap 15.6 (#151)

## v0.14.0 (2026-11-07)

### Features

- **distros**: drop Debian 12, past its security support (#150)

## v0.13.0 (2026-11-07)

### Features

- migrate renamed settings in config.sh after the user agrees (#139)

## v0.12.0 (2026-11-07)

### Features

- let Paste config save the text as a new shell file (#138)

## v0.11.0 (2026-11-06)

### Features

- **shell**: add an envsetup command to new shells (#129)

## v0.10.0 (2026-11-06)

### Features

- add --status and Check status to check the setup (#132)

## v0.9.0 (2026-11-06)

### Features

- **installers**: update tools that envsetup installed to the new pins (#131)
- **shell**: load your own shell files from shell.d (#130)

## v0.8.1 (2026-11-06)

### Fixes

- **git**: use diff3, which git 2.34 understands (#119)

## v0.8.0 (2026-11-06)

### Breaking changes

- show how to install git instead of installing it (#118)

## v0.7.0 (2026-11-06)

### Features

- add a Paste config action and check config edits (#116)

## v0.6.0 (2026-11-05)

### Features

- get config.sh from your own git repo with ENVSETUP_CONFIG_REPO (#115)

## v0.5.0 (2026-11-05)

### Features

- add a Set up SSH key action (#113)

## v0.4.2 (2026-11-05)

### Refactoring

- apply the writing rules to comments, messages and docs (#114)

## v0.4.1 (2026-11-03)

### Fixes

- **installers**: bump pinned tool versions (#109)

## v0.4.0 (2026-11-02)

### Breaking changes

- support Linux only and drop macOS (#108)

## v0.3.0 (2026-11-01)

### Breaking changes

- install.sh no longer keeps a checkout and ignores ENVSETUP_DIR; update with the curl command, not ~/envsetup/install.sh. An existing block that loads shell/ from ~/envsetup is rewritten in place, and Link shell config asks "Keep ~/envsetup?" (default: keep). A manual git clone still works, and envsetup never deletes it.
- run envsetup from a temporary download and keep only the shell config (#92)

### Fixes

- **packages**: refresh apt once per session and install in one batch (#91)

### Refactoring

- resolve "latest" only in the weekly bump, never at install time (#88)

## v0.2.2 (2026-10-27)

### Fixes

- **packages**: install gnupg on work so awscli's signature can be checked (#84)

## v0.2.1 (2026-10-26)

### Fixes

- **installers**: bump pinned tool versions (#83)

## v0.2.0 (2026-10-23)

### Features

- **installers**: pin every downloaded tool's version and sha256 in the repo (#81)

## v0.1.10 (2026-10-23)

### Fixes

- **xdg**: refuse dotfile notes that export BASH_ENV, LD_* or leave the XDG dir (#79)

## v0.1.9 (2026-10-23)

### Fixes

- name the config.sh envsetup reads when install.sh can't switch versions (#75)
- **xdg**: keep track of dotfiles uninstall can't move back (#74)

### Refactoring

- reuse install_release in helm.sh and keep set -e in the zsh step (#76)

## v0.1.8 (2026-10-23)

### Fixes

- **git**: stop deleting local tags on fetch, and document the opinionated git defaults (#71)

## v0.1.7 (2026-10-23)

### Fixes

- **shell**: make the multi-repo helpers report failures, and make resetNode check for a chart (#70)

## v0.1.6 (2026-10-23)

### Fixes

- **shell**: correct RESET_BOLD, keep the user's color variables, and stop colors when NO_COLOR is set (#69)

## v0.1.5 (2026-10-23)

### Fixes

- keep the caller's set options in load_config, and warn about errors in config.sh (#68)

## v0.1.4 (2026-10-23)

### Fixes

- **git**: save no empty user.name or user.email when the prompt is cancelled (#67)

## v0.1.3 (2026-10-12)

### Fixes

- keep the user's XDG_* and EDITOR values, and follow XDG_CONFIG_HOME (#66)

## v0.1.2 (2026-10-12)

### Fixes

- **shell**: build the bash prompt without running kubectl or a subshell per part (#65)
- load only PATH and exports in non-interactive shells (#64)
- **installers**: verify kubectl, gh, terraform and awscli before installing them (#63)

## v0.1.1 (2026-10-12)

### Fixes

- make pruneBranches list and ask, and keep unmerged branches (#62)

## v0.1.0 (2026-10-07)

### Breaking changes

- a checkout updated by install.sh is now a detached release, so `git pull` in it no longer updates it. Re-run install.sh instead, or set ENVSETUP_VERSION=main to keep following the main branch.
- versioned GitHub releases from Conventional Commits, and installing any of them (#54)
- **home**: make zsh an opt-in menu action; link ~/.bashrc everywhere (#26)
- rewrite to use gum with bash
- **installers**: tar on minimal images, helm without openssl, docker per distro (#27)

### Features

- **installers**: install with Homebrew on macOS (#32)
- bootstrap on macOS: Command Line Tools, Homebrew, a newer bash (#31)
- link the login shell's rc file, not just ~/.bashrc (#30)
- support the popular tools people add, not just the defaults (#29)
- **packages**: support zypper, apk, nix, EPEL and immutable distros (#25)
- optionally move dotfiles into XDG directories with xdg-ninja's notes (#21)
- ship my prompt, aliases, exports and shell functions (#20)
- **git**: ship my git aliases and settings as the defaults (#19)
- land --dry-run and --uninstall on main (#16, #17) (#18)
- make setup.sh explain itself to first-time users (#15)
- **config**: let users override every default from one config file (#12)
- **git**: add git identity + shared config setup (#11)
- add curl-pipeable install.sh bootstrap script (#6)
- **packages**: add sensible defaults per profile (#5)
- **installers**: add terraform, helm, awscli, gh for work profile (#8)
- **installers**: add pluggable third-party/custom installer scripts (#7)
- add home zsh/oh-my-zsh setup and work lite/full modes (#4)

### Fixes

- shell config that works with macOS's BSD tools (#33)
- **installers**: install gzip too on images that lack it (#28)
- don't let one package or step sink the rest of "Run everything" (#22)
- first-run crash, silent oh-my-zsh failures, and 4 more bugs (#13)

### Refactoring

- simplify setup.sh and lib/, consistent names, fewer restating comments (#23)
