#!/usr/bin/env bash
# Undoes what setup.sh added to this machine: the block in your shell rc files, the
# git include and its generated file, and envsetup's saved state. Leaves alone what
# it can't safely undo (packages and tools that may have been there before, your git
# identity) and says so. Honors the dry run like every other step.

# Removes complete envsetup blocks (begin marker through end marker) from a file,
# writing through symlinks. A begin marker with no end marker is left alone rather
# than taking everything after it with it.
envsetup::strip_block() {
	local tmp
	tmp=$(mktemp) || return 1
	awk -v b="$RC_MARKER_BEGIN" -v e="$RC_MARKER_END" '
		$0 == b { held = $0 ORS; inside = 1; next }
		inside { held = held $0 ORS; if ($0 == e) { inside = 0; held = "" }; next }
		{ print }
		END { if (inside) printf "%s", held }
	' "$1" >"$tmp" && cat "$tmp" >"$1"
	local rc=$?
	rm -f "$tmp"
	return "$rc"
}

# Returns 0 when it removed things, 2 when you backed out, 1 if a step failed. It's
# run where set -e doesn't apply, so each step reports its own failure.
envsetup::uninstall() {
	local state="$HOME/.config/envsetup" failed=0 rc f re kept=() mine=()
	local gitconfig="$state/gitconfig"
	gum style --bold "Removes what envsetup added: its block in your shell rc files, its git" \
		"include and its saved state. Packages and tools it installed stay."
	if ! gum confirm "Remove envsetup from this machine?"; then
		gum style "Nothing removed."
		return 2
	fi

	for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
		if [[ ! -f "$rc" ]] || ! grep -qxF "$RC_MARKER_BEGIN" "$rc"; then continue; fi
		if envsetup::dry_run; then
			envsetup::would "remove the envsetup block from $rc"
		elif envsetup::strip_block "$rc"; then
			gum style --foreground 2 "Removed the envsetup block from $rc"
		else
			gum style --foreground 1 "Couldn't edit $rc"
			failed=1
		fi
	done

	if git config --global --get-all include.path 2>/dev/null | grep -qxF "$gitconfig"; then
		if envsetup::dry_run; then
			envsetup::would "remove the include of $gitconfig from ~/.gitconfig"
		else
			re=$(printf '%s' "$gitconfig" | sed 's/[][\.*^$+?(){}|]/\\&/g')
			if git config --global --unset-all include.path "^$re\$"; then
				gum style --foreground 2 "Removed envsetup's include from ~/.gitconfig"
			else
				gum style --foreground 1 "Couldn't edit ~/.gitconfig"
				failed=1
			fi
		fi
	fi

	for f in "$gitconfig" "$gitconfig.tmp" "$state/profile" "$state/mode"; do
		[[ -e "$f" ]] || continue
		if envsetup::dry_run; then envsetup::would "delete $f"; else rm -f "$f"; fi
	done
	for f in "$state/config.sh" "$state/holidays.txt"; do
		[[ -f "$f" ]] && mine+=("$f")
	done
	if ((${#mine[@]})); then
		if gum confirm "Keep your own files (${mine[*]})? Only envsetup reads them."; then
			kept+=("your files: ${mine[*]}")
		elif envsetup::dry_run; then
			envsetup::would "delete ${mine[*]}"
		else
			rm -f "${mine[@]}"
		fi
	fi
	envsetup::dry_run || rmdir "$state" 2>/dev/null || true

	# Only asked if envsetup would have put you on zsh; a zsh you chose yourself is yours.
	if [[ "${SHELL:-}" == */zsh && "$ENVSETUP_SHELL" == zsh ]]; then
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
