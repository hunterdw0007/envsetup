#!/usr/bin/env bash
# This file holds "Configure git".
# ENVSETUP_GIT_CONFIG combines git/gitconfig and config.sh, and later entries win.
# "Configure git" writes it to a generated file, and ~/.gitconfig includes that file.
# Then it asks for any missing name or email.
# It never needs sudo, so work lite gets it too.

ENVSETUP_GIT_GENERATED="$ENVSETUP_STATE/gitconfig"

envsetup::git_included() {
	git config --global --get-all include.path 2>/dev/null | grep -qxF "$ENVSETUP_GIT_GENERATED"
}

# git_unset <key> is for the dry run.
# It is true if <key> would still have no value after a real run.
# That means neither ENVSETUP_GIT_CONFIG nor ~/.gitconfig with its includes sets <key>.
envsetup::git_unset() {
	local kv key
	for kv in "${ENVSETUP_GIT_CONFIG[@]}"; do
		key=${kv%%=*}
		[[ "${key,,}" == "${1,,}" ]] && return 1 # git keys are case-insensitive
	done
	[[ -z "$(git config --global --includes "$1" 2>/dev/null)" ]]
}

envsetup::configure_git() {
	local generated=$ENVSETUP_GIT_GENERATED kv key value
	local -A hint=([name]='Your name' [email]='you@example.com')
	if envsetup::dry_run; then
		if envsetup::git_included; then
			envsetup::would "rewrite $generated (${#ENVSETUP_GIT_CONFIG[@]} git settings)"
		else
			envsetup::would "write ${#ENVSETUP_GIT_CONFIG[@]} git settings to $generated and include it from ~/.gitconfig"
		fi
		for key in name email; do
			if envsetup::git_unset "user.$key"; then envsetup::would "ask for your git user.$key"; fi
		done
		return 0
	fi

	# The function writes the file again from the start.
	# So entries that you remove from config.sh also go away.
	# It writes to a temporary file first.
	# So a bad entry leaves the last good file in place.
	# --add keeps git's rules: the last value wins, and keys with more than one value collect them all.
	mkdir -p "${generated%/*}"
	echo "# envsetup generates this file from git/gitconfig and config.sh. It overwrites any edits." >"$generated.tmp"
	for kv in "${ENVSETUP_GIT_CONFIG[@]}"; do
		git config --file "$generated.tmp" --add "${kv%%=*}" "${kv#*=}"
	done
	mv "$generated.tmp" "$generated"
	if envsetup::git_included; then
		gum style --foreground 2 "Updated $generated"
	else
		git config --global --add include.path "$generated"
		gum style --foreground 2 "Included $generated in \$HOME/.gitconfig"
	fi

	# --includes is needed, because the name and email may come from config.sh through the generated file.
	# An empty answer skips the key.
	# Esc or Ctrl-C also skips it, because gum then exits non-zero.
	# So ~/.gitconfig never gets an empty user.name or user.email.
	for key in name email; do
		[[ -z "$(git config --global --includes "user.$key" 2>/dev/null)" ]] || continue
		if value=$(gum input --placeholder "${hint[$key]}") && [[ -n "${value//[[:space:]]/}" ]]; then
			if [[ "$key" == email && "$value" != *@* ]]; then
				gum style --foreground 3 "Skipped user.email: \"$value\" is not an email address"
			else
				git config --global "user.$key" "$value"
			fi
		else
			gum style --foreground 3 "Skipped user.$key. git needs it before your first commit: git config --global user.$key ..."
		fi
	done
}
