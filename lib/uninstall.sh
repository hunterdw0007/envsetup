#!/usr/bin/env bash
# This file removes what setup.sh added.
# That is the startup file block, the copy of shell/, the git include and its generated file, and the saved choices.
# Uninstall cannot safely remove packages or the git name and email.
# So it keeps them, and it says so.

# remove_rc_block <file> [replacement] removes each complete envsetup block from a file.
# A block runs from the begin marker to the end marker.
# With a replacement, the function puts the replacement in the block's place.
# It writes through symlinks.
# It leaves a begin marker without an end marker in place.
# Otherwise it would remove everything after that marker.
envsetup::remove_rc_block() {
	local tmp rc
	tmp=$(mktemp) || return 1
	# The replacement goes through the environment.
	# awk -v would turn the backslashes from %q into escapes.
	ENVSETUP_RC_NEW=${2:-} awk -v b="$ENVSETUP_RC_BEGIN" -v e="$ENVSETUP_RC_END" '
		$0 == b { held = $0 ORS; inside = 1; next }
		inside { held = held $0 ORS; if ($0 == e) { inside = 0; held = ""; printf "%s", ENVIRON["ENVSETUP_RC_NEW"] }; next }
		{ print }
		END { if (inside) printf "%s", held }
	' "$1" >"$tmp" && cat "$tmp" >"$1"
	rc=$?
	rm -f "$tmp"
	return "$rc"
}

# uninstall returns 0 after it removes things.
# It returns 2 when you cancel, and 1 when a step fails.
# set -e does not apply where it runs, so each step reports its own failure.
envsetup::uninstall() {
	local state=$ENVSETUP_STATE gitconfig=$ENVSETUP_GIT_GENERATED failed=0 chsh_by_us=0 rc f re kept=()
	gum style --bold "Uninstall removes what envsetup added." \
		"That is its block in your shell startup files, the copy of its shell config," \
		"its git include and its saved choices." \
		"Uninstall also moves back any dotfiles that envsetup moved." \
		"The packages and tools that envsetup installed stay."
	if ! gum confirm "Remove envsetup from this machine?"; then
		gum style "Uninstall removed nothing."
		return 2
	fi

	[[ -f "$ENVSETUP_CHSH_MARKER" ]] && chsh_by_us=1 # read this before the state folder is deleted
	for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
		if [[ ! -f "$rc" ]] || ! grep -qxF "$ENVSETUP_RC_BEGIN" "$rc"; then continue; fi
		if envsetup::dry_run; then
			envsetup::would "remove the envsetup block from $rc"
		elif envsetup::remove_rc_block "$rc"; then
			gum style --foreground 2 "Removed the envsetup block from $rc"
		else
			gum style --foreground 1 "Couldn't edit $rc"
			failed=1
		fi
	done

	if envsetup::git_included; then
		if envsetup::dry_run; then
			envsetup::would "remove the include of $gitconfig from ~/.gitconfig"
		else
			# --unset-all takes a regular expression.
			# So escape the path, and then it matches only itself.
			re=$(printf '%s' "$gitconfig" | sed 's/[][\.*^$+?(){}|]/\\&/g')
			if git config --global --unset-all include.path "^$re\$"; then
				gum style --foreground 2 "Removed envsetup's include from ~/.gitconfig"
			else
				gum style --foreground 1 "Couldn't edit ~/.gitconfig"
				failed=1
			fi
		fi
	fi

	envsetup::xdg_restore || failed=1

	# The last two files are the prompt's saved Kubernetes context (shell/shared/ps1.sh).
	# And the log of fetchAll --quiet (shell/shared/functions.sh).
	for f in "$gitconfig" "$gitconfig.tmp" "$state/profile" "$state/mode" "$ENVSETUP_CHSH_MARKER" "$ENVSETUP_DATA" \
		"${XDG_CACHE_HOME:-$HOME/.cache}/envsetup/kube-context" "${XDG_CACHE_HOME:-$HOME/.cache}/envsetup/fetchAll.log"; do
		[[ -e "$f" ]] || continue
		if envsetup::dry_run; then envsetup::would "delete $f"; else rm -rf "$f"; fi
	done
	if [[ -f "$state/config.sh" ]]; then
		if gum confirm "Keep your own config ($state/config.sh)? Only envsetup reads it."; then
			kept+=("your config: $state/config.sh")
		elif envsetup::dry_run; then
			envsetup::would "delete $state/config.sh"
		else
			rm -f "$state/config.sh"
		fi
	fi
	envsetup::dry_run || rmdir "$state" "${XDG_CACHE_HOME:-$HOME/.cache}/envsetup" 2>/dev/null || true

	# Uninstall asks only if envsetup changed your login shell to zsh.
	# It leaves a zsh that you chose yourself alone.
	if [[ "${SHELL:-}" == */zsh ]] && ((chsh_by_us)); then
		if gum confirm "Keep zsh as your login shell?"; then
			kept+=("zsh as your login shell")
		elif envsetup::dry_run; then
			envsetup::would "change your login shell back to bash (chsh)"
		elif ! chsh -s "$(command -v bash)"; then
			gum style --foreground 1 "Couldn't change your login shell"
			failed=1
		fi
	fi

	[[ -d "$HOME/.oh-my-zsh" ]] && kept+=("oh-my-zsh: remove it with uninstall_oh_my_zsh")
	gum style "Left in place:" \
		"- the packages and tools that envsetup installed. They may be older than envsetup, so remove them yourself." \
		"- your git user.name and user.email" \
		"${kept[@]/#/- }"
	return "$failed"
}
