#!/usr/bin/env bash
# "Set up SSH key": creates this machine's SSH key once, then offers to add it to GitHub
# and to sign git commits with it. Never needs sudo, so work lite gets it too.

# True if git already has a signing key or signs commits, e.g. with GPG. envsetup then
# leaves signing alone, so it never replaces settings of yours.
envsetup::git_signs() {
	[[ -n "$(git config --global --includes user.signingkey)$(git config --global --includes commit.gpgsign)" ]]
}

envsetup::set_up_ssh_key() {
	local key=$HOME/.ssh/id_ed25519 url=https://github.com/settings/keys comment
	# GitHub advises one key per machine; the comment names the machine in a list of keys.
	comment="$(id -un)@$HOSTNAME"
	if [[ -e "$key" ]]; then
		gum style --foreground 3 "Already have an SSH key: $key"
		return 0
	fi
	if ! envsetup::has_cmd ssh-keygen; then
		gum style --foreground 1 "ssh-keygen is not installed. Install openssh-client, then run Set up SSH key again."
		return 1
	fi
	if envsetup::dry_run; then
		envsetup::would "create the SSH key $key ($comment) and ask for its passphrase"
		if envsetup::has_cmd gh; then
			envsetup::would "ask to add it to your GitHub account with gh"
		else
			envsetup::would "show the public key, to add at $url"
		fi
		if ! envsetup::git_signs; then envsetup::would "ask to sign your git commits with it"; fi
		return 0
	fi

	[[ -d "$HOME/.ssh" ]] || mkdir -m 700 "$HOME/.ssh"
	# ssh-keygen asks for the passphrase itself, so it never shows up in a process list.
	ssh-keygen -t ed25519 -C "$comment" -f "$key"
	# Noted so uninstall offers to delete only a key envsetup created.
	mkdir -p "${ENVSETUP_SSH_KEY_MARKER%/*}"
	: >"$ENVSETUP_SSH_KEY_MARKER"
	gum style --foreground 2 "Created the SSH key $key"

	# gh fails when it isn't logged in or lacks the admin:public_key scope; the key then shows instead.
	if envsetup::has_cmd gh && gum confirm "Add the key to your GitHub account with gh?" &&
		gh ssh-key add "$key.pub" --title "$comment"; then
		gum style --foreground 2 "Added the key to your GitHub account"
	else
		gum style "Add this public key at $url:" "$(<"$key.pub")"
	fi

	if envsetup::git_signs; then
		gum style --foreground 3 "git already has signing settings, so envsetup leaves them as they are."
	elif gum confirm "Sign your git commits with this key?"; then
		git config --global gpg.format ssh
		git config --global user.signingkey "$key.pub"
		git config --global commit.gpgsign true
		gum style --foreground 2 "git now signs your commits with $key"
	fi
}
