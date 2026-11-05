#!/usr/bin/env bash
# This file holds "Set up SSH key".
# The action creates this machine's SSH key once.
# It then offers to add the key to GitHub and to sign git commits with it.
# The action needs no sudo, so work lite runs it too.

# git_signs returns 0 if git already has a signing key or already signs commits.
# GPG signing is an example.
# envsetup then leaves signing alone, so it never replaces your own settings.
envsetup::git_signs() {
	[[ -n "$(git config --global --includes user.signingkey)$(git config --global --includes commit.gpgsign)" ]]
}

envsetup::set_up_ssh_key() {
	local key=$HOME/.ssh/id_ed25519 url=https://github.com/settings/keys comment use_gh=0
	# GitHub advises one key per machine.
	# The comment names the machine in a list of keys.
	comment="$(id -un)@$HOSTNAME"
	if [[ -e "$key" ]]; then
		gum style --foreground 3 "An SSH key already exists: $key"
		return 0
	fi
	if ! envsetup::has_cmd ssh-keygen; then
		gum style --foreground 1 "This machine has no ssh-keygen. Install openssh-client. Then run Set up SSH key again."
		return 1
	fi
	if envsetup::dry_run; then
		envsetup::would "create the SSH key $key ($comment)"
		envsetup::would "let ssh-keygen ask for a passphrase"
		if envsetup::has_cmd gh; then
			envsetup::would "ask to add it to your GitHub account with gh"
		else
			envsetup::would "show the public key, to add at $url"
		fi
		if ! envsetup::git_signs; then
			envsetup::would "ask to sign your git commits with it"
			if envsetup::has_cmd gh; then
				envsetup::would "add it to your GitHub account as a signing key with gh, if you say yes to both questions"
			else
				envsetup::would "show where to add it as a signing key, if you say yes to signing: $url"
			fi
		fi
		return 0
	fi

	[[ -d "$HOME/.ssh" ]] || mkdir -m 700 "$HOME/.ssh"
	# ssh-keygen asks for the passphrase itself.
	# So the passphrase never shows in a process list.
	ssh-keygen -t ed25519 -C "$comment" -f "$key"
	# The marker lets uninstall offer to delete only a key that envsetup created.
	mkdir -p "${ENVSETUP_SSH_KEY_MARKER%/*}"
	: >"$ENVSETUP_SSH_KEY_MARKER"
	gum style --foreground 2 "Created the SSH key $key"

	# After a no here, the action also uploads no signing key below.
	if envsetup::has_cmd gh && gum confirm "Add the key to your GitHub account with gh?"; then use_gh=1; fi
	# gh fails when it has no login or no admin:public_key scope.
	# The action then shows the key instead.
	if ((use_gh)) && gh ssh-key add "$key.pub" --title "$comment"; then
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
		# GitHub marks a signed commit "Verified" only when it has the key as a signing key.
		# gh exits 0 when GitHub already has the key.
		# gh fails without the admin:ssh_signing_key scope.
		# The action then says where to add the key instead.
		if ((use_gh)) && gh ssh-key add "$key.pub" --type signing --title "$comment signing"; then
			gum style --foreground 2 "Added the key to your GitHub account as a signing key"
		else
			gum style --foreground 3 "Add the public key as a signing key at $url (key type \"Signing Key\")"
		fi
	fi
}
