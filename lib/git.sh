#!/usr/bin/env bash
# Sets up git: includes this repo's shared aliases/settings into ~/.gitconfig, and
# prompts for identity (user.name/user.email) if it isn't already set. Runs
# regardless of profile/mode — it only ever writes to $HOME/.gitconfig, no sudo.

envsetup::setup_git() {
	local gitconfig="$ENVSETUP_ROOT/git/gitconfig"

	if ! git config --global --get-all include.path 2>/dev/null | grep -qxF "$gitconfig"; then
		git config --global --add include.path "$gitconfig"
		gum style --foreground 2 "Included $gitconfig in \$HOME/.gitconfig"
	else
		gum style --foreground 3 "\$HOME/.gitconfig already includes $gitconfig"
	fi

	if [[ -z "$(git config --global user.name 2>/dev/null)" ]]; then
		git config --global user.name "$(gum input --placeholder 'Your name')"
	fi

	if [[ -z "$(git config --global user.email 2>/dev/null)" ]]; then
		git config --global user.email "$(gum input --placeholder 'you@example.com')"
	fi
}
