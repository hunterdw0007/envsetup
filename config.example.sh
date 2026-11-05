# shellcheck shell=bash
# This is your envsetup config.
# It lives at ~/.config/envsetup/config.sh.
# If you set XDG_CONFIG_HOME, it lives at $XDG_CONFIG_HOME/envsetup/config.sh.
# This file is outside the repo, so an envsetup update never changes it.
# To keep this file in your own git repo, set ENVSETUP_CONFIG_REPO in the curl command.
# For example, ENVSETUP_CONFIG_REPO=github.com/me/dotfiles uses the config.sh at the top of that repo.
# ENVSETUP_CONFIG_REPO=me is short for github.com/me/envsetup-config.
# envsetup clones the repo into ~/.config/envsetup/repo and links this file to it.
# Each later run pulls the repo again.
# New shells load the copy of shell/ in ~/.local/share/envsetup.
# Put your own changes in this file, not in that copy.
# "Edit config" in the menu copies this template to that path and opens it in $EDITOR.
#
# This file is a bash script.
# envsetup sources it after the repo defaults, in two places:
#   - setup.sh sources it and acts on the ENVSETUP_* settings below.
#   - Every new shell sources it through shell/init.sh, so your aliases, exports and functions load too.
# Every line is commented out, so this template changes nothing.
#
# $ENVSETUP_PROFILE (work or home) and $ENVSETUP_MODE (full or lite) let you change settings for each machine.
# If you set up zsh, zsh also runs this file.
# So write code that works in bash and zsh.
# Or wrap bash-only code in [[ -n $BASH_VERSION ]].
# setup.sh also sources this file in a non-interactive shell.
# So wrap code for interactive shells only in [[ $- == *i* ]].
# Prompt frameworks and completions are examples.
#
# setup.sh sources this file in its own process.
# So `exit` in this file stops setup.sh.
# And `cd` in this file changes setup.sh's folder.
# A syntax error or a failed command in this file makes setup.sh show a warning.
# setup.sh then continues with the settings that loaded.

# --- Packages ---------------------------------------------------------------------
# The defaults are packages/common.txt and packages/$ENVSETUP_PROFILE.txt.
# Use the Debian or Ubuntu name.
# packages/names.txt translates the name for other distros.
# envsetup passes any other name to the package manager unchanged.
# ENVSETUP_PACKAGES+=(neovim)          # add to the defaults
# ENVSETUP_PACKAGES=(git tmux curl)    # or replace the defaults
# [[ $ENVSETUP_PROFILE == work ]] && ENVSETUP_PACKAGES+=(kubectx)

# --- Extra tools --------------------------------------------------------------------
# Ubuntu LTS and Fedora do not package these popular tools.
# "Run installers" installs them from each project's own releases.
# The extras are starship, lazygit, k9s, yq, mise and uv (installers/extras/).
# ENVSETUP_EXTRAS=(lazygit k9s)

# --- Installer scripts ------------------------------------------------------------
# The defaults are installers/common and installers/$ENVSETUP_PROFILE.
# ENVSETUP_INSTALLER_DIRS+=("$HOME/dotfiles/envsetup-installers")   # your own scripts

# --- Skip ---------------------------------------------------------------------------
# List any package or installer to skip, by name.
# An installer's name is its script name without .sh.
# ENVSETUP_SKIP=(docker terraform awscli)

# --- Dotfiles in XDG folders --------------------------------------------------------
# The default is 0.
# The value 1 adds "Move dotfiles to XDG dirs" to "Run everything".
# That action moves dotfiles into ~/.config, ~/.local and ~/.cache.
# It moves a dotfile only when xdg-ninja's note gives simple steps.
# ENVSETUP_XDG_NINJA=1

# --- Login shell --------------------------------------------------------------------
# The default is bash.
# envsetup always links ~/.bashrc and your login shell's startup file.
# The value zsh adds "Set up zsh + oh-my-zsh" to "Run everything".
# That action installs zsh and oh-my-zsh and links ~/.zshrc.
# ENVSETUP_SHELL=zsh

# --- Git ----------------------------------------------------------------------------
# The defaults come from git/gitconfig.
# Each entry is key=value, the same format as `git config --list`.
# So you can paste the output of `git config --global --list` from another machine.
# Later entries win, so these entries replace the defaults.
# Run "Configure git" again to apply a change.
# ENVSETUP_GIT_CONFIG+=(
# 	"user.name=Your Name"
# 	"user.email=you@example.com"
# 	"pull.rebase=false"
# )
# Some keys can hold more than one value, for example credential.helper.
# A new value for such a key adds to the defaults and does not replace them.
# An empty value clears the list first.
# For example, this keeps HTTPS passwords on disk instead of in memory for one hour.
# git stores them as plain text in ~/.git-credentials.
# ENVSETUP_GIT_CONFIG+=("credential.helper=" "credential.helper=store")
# On WSL, this uses the Git Credential Manager of Windows:
# ENVSETUP_GIT_CONFIG+=("credential.helper=" "credential.helper=/mnt/c/Program\ Files/Git/mingw64/bin/git-credential-manager.exe")
# Settings for one machine go here too, for example on a work machine:
# [[ $ENVSETUP_PROFILE == work ]] && ENVSETUP_GIT_CONFIG+=(
# 	"core.hooksPath=$HOME/.git-templates/hooks"
# 	"http.sslCAInfo=$HOME/.config/corp-ca-bundle.crt"
# )

# --- Shell --------------------------------------------------------------------------
# Everything else is normal shell config.
# It loads after the defaults in the repo's shell/ folder, so it can add to them or replace them.
# A change takes effect in the next new shell.
# You do not need to run setup again.
# alias k=kubectl
# unalias ll 2>/dev/null
# export EDITOR=nvim
# alias code='"/mnt/c/Users/<you>/AppData/Local/Programs/Microsoft VS Code/bin/code"'  # WSL
