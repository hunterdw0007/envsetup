#!/usr/bin/env bash
# Gets a machine onto zsh + oh-my-zsh (used for the home profile).

envsetup::setup_zsh() {
	if ! envsetup::has_cmd zsh; then
		local manager
		manager="$(envsetup::pkg_manager)"
		if [[ -z "$manager" ]]; then
			gum style --foreground 1 "No supported package manager found to install zsh."
			return 1
		fi
		gum style --bold "Installing zsh..."
		envsetup::install_packages "$manager" zsh
	fi

	if [[ "$SHELL" != */zsh ]] && gum confirm "Set zsh as your default login shell?"; then
		chsh -s "$(command -v zsh)"
	fi

	if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
		gum style --bold "Installing oh-my-zsh..."
		RUNZSH=no KEEP_ZSHRC=yes sh -c \
			"$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
	fi
}
