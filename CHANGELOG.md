# Changelog

Every release of envsetup, newest first, with what changed in it. CI writes each entry
from the commits on `main` when it releases them (see "Releases" in AGENTS.md), so
don't edit this file by hand.

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
