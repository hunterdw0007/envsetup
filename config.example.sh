# shellcheck shell=bash
# envsetup user config. Lives at ~/.config/envsetup/config.sh, outside this repo, so
# updating envsetup (git pull / re-running install.sh) never conflicts with it.
# "Edit config" in ./setup.sh copies this file there and opens it in $EDITOR.
#
# It's plain bash, sourced *after* the repo defaults in two places:
#   - by setup.sh, which acts on the ENVSETUP_* variables below
#   - by every new shell (via shell/init.sh), so aliases/exports/functions here load too
# Everything is commented out, so this file as shipped changes nothing.
#
# Branch on $ENVSETUP_PROFILE (work | home) and $ENVSETUP_MODE (full | lite) for
# per-machine tweaks. On the home profile your shell is zsh, so keep shell code
# portable (or guard bash-only bits with [[ -n $BASH_VERSION ]]), and put
# interactive-only things (prompt frameworks, completions) under [[ $- == *i* ]],
# since setup.sh sources this file non-interactively too.

# --- Packages ---------------------------------------------------------------------
# Defaults: packages/common.txt + packages/$ENVSETUP_PROFILE.txt. Use Debian/Ubuntu's
# names; packages/names.txt translates them for other distros (others pass through).
# ENVSETUP_PACKAGES+=(neovim)          # add to the defaults
# ENVSETUP_PACKAGES=(git tmux curl)    # or replace them entirely
# [[ $ENVSETUP_PROFILE == work ]] && ENVSETUP_PACKAGES+=(kubectx)

# --- Installer scripts ------------------------------------------------------------
# Defaults: installers/common + installers/$ENVSETUP_PROFILE
# ENVSETUP_INSTALLER_DIRS+=("$HOME/dotfiles/envsetup-installers")   # your own scripts

# --- Skip ---------------------------------------------------------------------------
# Leave out any package or installer by name (installer = script name without .sh).
# ENVSETUP_SKIP=(docker.io terraform awscli)

# --- Dotfiles in XDG directories -----------------------------------------------------
# Default: 0. 1 makes "Run everything" also run "Move dotfiles to XDG dirs", which moves
# dotfiles into ~/.config, ~/.local and ~/.cache where xdg-ninja says it's mechanical.
# ENVSETUP_XDG_NINJA=1

# --- Login shell --------------------------------------------------------------------
# Default: zsh (+ oh-my-zsh) on home, bash otherwise. Decides which rc file gets
# linked and whether zsh/oh-my-zsh are installed.
# ENVSETUP_SHELL=bash

# --- Git ----------------------------------------------------------------------------
# Defaults: git/gitconfig. key=value, same format as `git config --list`, so you can
# paste straight from `git config --global --list` on an existing machine. Later
# entries win, so these override the defaults. Re-run "Configure git" to apply.
# ENVSETUP_GIT_CONFIG+=(
# 	"user.name=Your Name"
# 	"user.email=you@example.com"
# 	"pull.rebase=false"
# )
# Multi-valued keys (credential.helper, ...) add to the defaults instead of replacing
# them; an empty value clears the list first. E.g. to keep HTTPS credentials on disk
# (plain text, in ~/.git-credentials) instead of in memory for an hour:
# ENVSETUP_GIT_CONFIG+=("credential.helper=" "credential.helper=store")
# Settings that only fit one machine go here too, e.g. on a work box:
# [[ $ENVSETUP_PROFILE == work ]] && ENVSETUP_GIT_CONFIG+=(
# 	"core.hooksPath=$HOME/.git-templates/hooks"
# 	"http.sslCAInfo=$HOME/.config/corp-ca-bundle.crt"
# )

# --- Shell --------------------------------------------------------------------------
# Anything else is ordinary shell config, loaded after the repo's shell/ defaults,
# so it can add to or override them. Changes apply to new shells, no setup re-run.
# alias k=kubectl
# unalias ll 2>/dev/null
# export EDITOR=nvim
# alias code='"/mnt/c/Users/<you>/AppData/Local/Programs/Microsoft VS Code/bin/code"'  # WSL
