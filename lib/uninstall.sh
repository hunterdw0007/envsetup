#!/usr/bin/env bash
# Undoes what setup.sh added: the rc-file block, the git include and its generated
# file, and the saved state. What it can't safely undo (packages, git identity) stays,
# and it says so.

# Removes complete envsetup blocks (begin marker through end marker) from a file,
# writing through symlinks. A begin marker with no end marker is left alone rather
# than taking everything after it with it.
envsetup::remove_rc_block() {
	local tmp rc
	tmp=$(mktemp) || return 1
	awk -v b="$ENVSETUP_RC_BEGIN" -v e="$ENVSETUP_RC_END" '
		$0 == b { held = $0 ORS; inside = 1; next }
		inside { held = held $0 ORS; if ($0 == e) { inside = 0; held = "" }; next }
		{ print }
		END { if (inside) printf "%s", held }
	' "$1" >"$tmp" && cat "$tmp" >"$1"
	rc=$?
	rm -f "$tmp"
	return "$rc"
}

# Returns 0 when it removed things, 2 when you backed out, 1 if a step failed. It runs
# where set -e doesn't apply, so each step reports its own failure.
envsetup::uninstall() {
	local state=$ENVSETUP_STATE gitconfig=$ENVSETUP_GIT_GENERATED failed=0 zsh_linked=0 rc f re kept=()
	gum style --bold "Removes what envsetup added: its block in your shell rc files, its git" \
		"include and its saved state, and moves back any dotfiles it moved. Packages and" \
		"tools it installed stay."
	if ! gum confirm "Remove envsetup from this machine?"; then
		gum style "Nothing removed."
		return 2
	fi

	for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
		if [[ ! -f "$rc" ]] || ! grep -qxF "$ENVSETUP_RC_BEGIN" "$rc"; then continue; fi
		[[ "$rc" == */.zshrc ]] && zsh_linked=1
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
			# --unset-all takes a regex; escape the path so it matches only itself.
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

	for f in "$gitconfig" "$gitconfig.tmp" "$state/profile" "$state/mode"; do
		[[ -e "$f" ]] || continue
		if envsetup::dry_run; then envsetup::would "delete $f"; else rm -f "$f"; fi
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
	envsetup::dry_run || rmdir "$state" 2>/dev/null || true

	# Only asked if envsetup set you up on zsh; a zsh you chose yourself is yours.
	if [[ "${SHELL:-}" == */zsh ]] && ((zsh_linked)); then
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
		"- packages and tools envsetup installed; they may predate it, so remove any yourself" \
		"- your git user.name/user.email" \
		"${kept[@]/#/- }" \
		"- envsetup itself: rm -rf $ENVSETUP_ROOT"
	return "$failed"
}
