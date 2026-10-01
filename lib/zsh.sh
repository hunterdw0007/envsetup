#!/usr/bin/env bash
# Gets a machine onto zsh + oh-my-zsh (the home profile). Called as `setup_zsh ||
# return 1`, which turns set -e off in here, so every failure has an explicit return.

envsetup::setup_zsh() {
	local missing=() manager installer
	envsetup::has_cmd zsh || missing+=(zsh)
	# The oh-my-zsh installer is fetched with curl, which a fresh desktop may not have yet.
	envsetup::has_cmd curl || missing+=(curl)
	if envsetup::dry_run; then
		((${#missing[@]} == 0)) || envsetup::would "install ${missing[*]} (sudo)"
		[[ "$SHELL" == */zsh ]] || envsetup::would "ask to make zsh your login shell (chsh)"
		[[ -d "$HOME/.oh-my-zsh" ]] || envsetup::would "install oh-my-zsh (runs its installer from github.com)"
		return 0
	fi
	if ((${#missing[@]} > 0)); then
		manager="$(envsetup::pkg_manager)"
		if [[ -z "$manager" ]]; then
			gum style --foreground 1 "No supported package manager found to install ${missing[*]}."
			return 1
		fi
		gum style --bold "Installing ${missing[*]}..."
		envsetup::pkg_install "$manager" "${missing[@]}" || return 1
	fi

	if [[ "$SHELL" != */zsh ]] && gum confirm "Set zsh as your default login shell?"; then
		chsh -s "$(command -v zsh)"
	fi

	if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
		gum style --bold "Installing oh-my-zsh..."
		# Not `sh -c "$(curl ...)"`: that runs an empty script and "succeeds" when the
		# download fails, leaving a ~/.zshrc that the next install attempt then keeps.
		if ! installer="$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"; then
			gum style --foreground 1 "Couldn't download the oh-my-zsh installer."
			return 1
		fi
		RUNZSH=no KEEP_ZSHRC=yes sh -c "$installer" || return 1
	fi
}
