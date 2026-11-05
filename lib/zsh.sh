#!/usr/bin/env bash
# This file sets up zsh + oh-my-zsh on a machine.
# The user opts in from the menu or with ENVSETUP_SHELL=zsh.
# It runs under the set -e of envsetup::run_step.

envsetup::install_zsh() {
	local missing=() manager installer commit
	envsetup::has_cmd zsh || missing+=(zsh)
	# curl downloads the oh-my-zsh installer, and a new desktop may not have curl yet.
	envsetup::has_cmd curl || missing+=(curl)
	# The base systems of Fedora and Alpine do not include chsh.
	envsetup::has_cmd chsh || missing+=(chsh)
	if ((${#missing[@]} > 0)) && envsetup::lite; then
		gum style --foreground 1 "work (lite) does not assume sudo, so it cannot install ${missing[*]}. Install it yourself, then run this again."
		return 1
	fi
	if envsetup::dry_run; then
		((${#missing[@]} == 0)) || envsetup::would "install ${missing[*]} (as root)"
		[[ "$SHELL" == */zsh ]] || envsetup::would "ask to make zsh your login shell (chsh)"
		[[ -d "$HOME/.oh-my-zsh" ]] || envsetup::would "install oh-my-zsh with its installer from github.com"
		return 0
	fi
	if ((${#missing[@]} > 0)); then
		manager="$(envsetup::pkg_manager)"
		if [[ -z "$manager" ]]; then
			gum style --foreground 1 "envsetup found no supported package manager to install ${missing[*]}."
			return 1
		fi
		gum style --bold "Installing ${missing[*]}..."
		envsetup::pkg_install "$manager" "${missing[@]}" || return 1
	fi

	if [[ "$SHELL" != */zsh ]] && gum confirm "Set zsh as your default login shell?"; then
		# envsetup records the change.
		# Uninstall then offers to change back only a login shell that envsetup changed.
		if chsh -s "$(command -v zsh)"; then
			mkdir -p "${ENVSETUP_CHSH_MARKER%/*}"
			: >"$ENVSETUP_CHSH_MARKER"
		fi
	fi

	if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
		gum style --bold "Installing oh-my-zsh..."
		# Do not use `sh -c "$(curl ...)"`.
		# When the download fails, that command runs an empty script and still succeeds.
		# It leaves a ~/.zshrc, and the next install keeps that file.
		# The installer comes from the commit pinned in installers/versions.txt.
		# The installer clones the newest oh-my-zsh, and oh-my-zsh then updates itself.
		if ! commit=$(envsetup::pin ohmyzsh) ||
			! installer="$(curl -fsSL "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/$commit/tools/install.sh")"; then
			gum style --foreground 1 "Couldn't download the oh-my-zsh installer."
			return 1
		fi
		# CHSH=no, because the question about the login shell came above.
		# Without it, the installer would ask again.
		RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$installer" || return 1
	fi
}
