#!/usr/bin/env bash
# Moves dotfiles out of $HOME into the XDG base directories, using xdg-ninja's
# per-program notes (https://github.com/b3nj5m1n/xdg-ninja). Those notes are prose for
# people, so only the two mechanical shapes are applied:
#   - exactly one `export VAR="$XDG_*_HOME"/path` and nothing else to do: move + export
#   - the program already reads the XDG path and the note names it: move only
# Anything with a version caveat, extra steps, a clash, or a reference from your rc
# files is left alone and listed. Every move is recorded so uninstall can put it back.
# The notes are downloaded data: they're matched against strict patterns, never run.

ENVSETUP_XDG_NINJA_URL=${ENVSETUP_XDG_NINJA_URL:-https://github.com/b3nj5m1n/xdg-ninja}
ENVSETUP_XDG_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/envsetup/xdg-ninja"
ENVSETUP_XDG_MOVES="$HOME/.config/envsetup/xdg-moves"
ENVSETUP_XDG_ENV="$HOME/.config/envsetup/xdg.sh"

# Files a shell or envsetup itself reads before any exports load, and variables that
# more than one program (or a running agent) depends on: never moved automatically.
_envsetup_xdg_keep_files=" .bashrc .bash_profile .bash_login .profile .zshrc .zshenv .zprofile .zlogin .gitconfig "
_envsetup_xdg_keep_vars=" HISTFILE ZDOTDIR GNUPGHOME "

# Prints "new path<TAB>VAR" for a note it can apply (VAR empty for move-only),
# returns 1 for anything else. (VAR goes last: read with IFS=$'\t' would swallow an
# empty first field.)
envsetup::xdg_target() {
	local help=$1 line code=() fenced=0 base sub var=""
	local xdg='\$\{?XDG_(CONFIG|DATA|STATE|CACHE)_HOME\}?' path='((/[A-Za-z0-9._-]+)+)'
	local caveat='version|since|commit|>=|<=' another='move the (file|directory|folder) to _'
	[[ "${help,,}" =~ $caveat ]] && return 1
	while IFS= read -r line; do
		if [[ "$line" == '```'* ]]; then
			fenced=$((!fenced))
		elif ((fenced)) && [[ "$line" =~ [^[:space:]] ]]; then
			code+=("$line")
		fi
	done <<<"$help"

	if ((${#code[@]} == 1)) && [[ "${code[0]}" =~ ^export\ ([A-Z_][A-Z0-9_]*)=\"?$xdg\"?$path\"?$ ]]; then
		var=${BASH_REMATCH[1]} base=${BASH_REMATCH[2]} sub=${BASH_REMATCH[3]}
	elif ((${#code[@]} == 0)) && [[ "$help" =~ ${another}${xdg}${path}_ ]]; then
		base=${BASH_REMATCH[2]} sub=${BASH_REMATCH[3]}
		# A second "move ... to" means several targets: not mechanical.
		[[ "${help#*"${BASH_REMATCH[0]}"}" =~ $another ]] && return 1
	else
		return 1
	fi
	case $base in
	CONFIG) base=${XDG_CONFIG_HOME:-$HOME/.config} ;;
	DATA) base=${XDG_DATA_HOME:-$HOME/.local/share} ;;
	STATE) base=${XDG_STATE_HOME:-$HOME/.local/state} ;;
	CACHE) base=${XDG_CACHE_HOME:-$HOME/.cache} ;;
	esac
	printf '%s\t%s\n' "$base$sub" "$var"
}

# One line per dotfile found in $HOME:
#   move<TAB>program<TAB>old<TAB>new<TAB>VAR
#   skip<TAB>program<TAB>old<TAB>reason
envsetup::xdg_plan() {
	local name path help old target var new rc rcs=() moves=() tilde='~' # as rc files spell it
	local -A var_count=()
	# Only existing files: grep exits 2, not 0, when a match comes with a missing file.
	for rc in "$HOME"/.{bashrc,bash_profile,profile,zshrc,zprofile,zshenv}; do
		[[ -f "$rc" ]] && rcs+=("$rc")
	done
	while IFS=$'\t' read -r name path help; do
		[[ "$path" =~ ^\$HOME/([A-Za-z0-9._-]+)$ ]] || continue
		old="$HOME/${BASH_REMATCH[1]}"
		[[ -e "$old" || -L "$old" ]] || continue
		printf -v help '%b' "$help" # undo @tsv's escaping
		if [[ -L "$old" ]]; then
			printf 'skip\t%s\t%s\t%s\n' "$name" "$old" "it's a symlink (managed by something else?)"
		elif [[ "$_envsetup_xdg_keep_files" == *" ${old##*/} "* ]]; then
			printf 'skip\t%s\t%s\t%s\n' "$name" "$old" "a shell or envsetup reads it at startup"
		elif ! target=$(envsetup::xdg_target "$help"); then
			printf 'skip\t%s\t%s\t%s\n' "$name" "$old" "needs manual steps (see xdg-ninja)"
		else
			IFS=$'\t' read -r new var <<<"$target"
			if [[ -n "$var" && "$_envsetup_xdg_keep_vars" == *" $var "* ]]; then
				printf 'skip\t%s\t%s\t%s\n' "$name" "$old" "\$$var is shared with other programs"
			elif [[ -n "$var" && -n "${!var+x}" ]]; then
				printf 'skip\t%s\t%s\t%s\n' "$name" "$old" "\$$var is already set"
			elif [[ -e "$new" || -L "$new" ]]; then
				printf 'skip\t%s\t%s\t%s\n' "$name" "$old" "$new already exists"
			elif ((${#rcs[@]})) && rc=$(grep -lF -e "$tilde/${old##*/}" -e "\$HOME/${old##*/}" -e "\${HOME}/${old##*/}" -e "$old" "${rcs[@]}"); then
				printf 'skip\t%s\t%s\t%s\n' "$name" "$old" "referenced from ${rc//$'\n'/, }"
			else
				moves+=("$name"$'\t'"$old"$'\t'"$new"$'\t'"$var")
				if [[ -n "$var" ]]; then var_count[$var]=$((${var_count[$var]:-0} + 1)); fi
			fi
		fi
	done < <(jq -r '.name as $n | .files[] | select(.movable) | [$n, .path, .help] | @tsv' "$ENVSETUP_XDG_CACHE"/programs/*.json)

	for target in "${moves[@]}"; do
		IFS=$'\t' read -r name old new var <<<"$target"
		if [[ -n "$var" ]] && ((var_count[$var] > 1)); then
			printf 'skip\t%s\t%s\t%s\n' "$name" "$old" "\$$var is claimed by more than one program"
		else
			printf 'move\t%s\n' "$target"
		fi
	done
}

# Clones xdg-ninja's notes into the cache, or refreshes them. An offline refresh
# falls back to the copy already there.
envsetup::xdg_fetch() {
	if [[ -d "$ENVSETUP_XDG_CACHE/.git" ]]; then
		envsetup::dry_run && return 0
		git -C "$ENVSETUP_XDG_CACHE" pull -q --ff-only ||
			gum style --foreground 3 "Couldn't update xdg-ninja's notes; using the copy from last time."
	elif envsetup::dry_run; then
		envsetup::would "download xdg-ninja's notes into $ENVSETUP_XDG_CACHE, then look for dotfiles to move"
		return 1
	else
		mkdir -p "${ENVSETUP_XDG_CACHE%/*}"
		git clone -q --depth 1 "$ENVSETUP_XDG_NINJA_URL" "$ENVSETUP_XDG_CACHE" || {
			gum style --foreground 1 "Couldn't download xdg-ninja's notes from $ENVSETUP_XDG_NINJA_URL"
			return 1
		}
	fi
}

# Rewrites the exports every shell loads (shell/init.sh) from the list of moves.
envsetup::xdg_write_env() {
	local old new var
	{
		echo "# Generated by envsetup from $ENVSETUP_XDG_MOVES; edits here are overwritten."
		while IFS=$'\t' read -r old new var; do
			if [[ -n "$var" ]]; then printf 'export %s=%q\n' "$var" "$new"; fi
		done <"$ENVSETUP_XDG_MOVES"
	} >"$ENVSETUP_XDG_ENV"
}

envsetup::xdg_tidy() {
	local line name old new var reason moves=() skips=() failed=0
	if ! envsetup::has_cmd jq || ! envsetup::has_cmd git; then
		gum style --foreground 3 "Moving dotfiles needs jq and git (both in packages/common.txt); skipping."
		return 0
	fi
	envsetup::xdg_fetch || return 0

	while IFS= read -r line; do
		if [[ "$line" == move$'\t'* ]]; then moves+=("${line#*$'\t'}"); else skips+=("${line#*$'\t'}"); fi
	done < <(envsetup::xdg_plan)

	for line in "${skips[@]}"; do
		IFS=$'\t' read -r name old reason <<<"$line"
		gum style --foreground 3 "  leaving ${old/#$HOME/\~} ($name): ${reason//$HOME/\~}"
	done
	if ((${#moves[@]} == 0)); then
		gum style "No dotfiles to move."
		return 0
	fi
	for line in "${moves[@]}"; do
		IFS=$'\t' read -r name old new var <<<"$line"
		line="move ${old/#$HOME/\~} to ${new/#$HOME/\~}"
		[[ -n "$var" ]] && line+=" and export $var"
		if envsetup::dry_run; then envsetup::would "$line"; else gum style "  $line"; fi
	done
	envsetup::dry_run && return 0
	gum confirm "Move these ${#moves[@]} dotfiles? Uninstall moves them back." || return 0

	mkdir -p "${ENVSETUP_XDG_MOVES%/*}"
	touch "$ENVSETUP_XDG_MOVES"
	for line in "${moves[@]}"; do
		IFS=$'\t' read -r name old new var <<<"$line"
		if mkdir -p "${new%/*}" && mv -n "$old" "$new" && [[ ! -e "$old" ]]; then
			printf '%s\t%s\t%s\n' "$old" "$new" "$var" >>"$ENVSETUP_XDG_MOVES"
		else
			gum style --foreground 1 "Couldn't move $old"
			failed=1
		fi
	done
	envsetup::xdg_write_env
	gum style --foreground 2 "Moved. New shells pick up the exports; programs already running still use the old paths."
	return "$failed"
}

# For uninstall: moves everything back (newest first), then drops the exports, the
# list of moves and the cached notes.
envsetup::xdg_restore() {
	local lines=() i old new var failed=0
	if [[ -f "$ENVSETUP_XDG_MOVES" ]]; then
		readarray -t lines <"$ENVSETUP_XDG_MOVES"
		for ((i = ${#lines[@]} - 1; i >= 0; i--)); do
			IFS=$'\t' read -r old new var <<<"${lines[i]}"
			[[ -e "$new" && ! -e "$old" ]] || continue
			if envsetup::dry_run; then
				envsetup::would "move $new back to $old"
			elif mv -n "$new" "$old"; then
				rmdir "${new%/*}" 2>/dev/null || true # the directory the move created, if now empty
			else
				gum style --foreground 1 "Couldn't move $new back to $old"
				failed=1
			fi
		done
	fi
	for var in "$ENVSETUP_XDG_MOVES" "$ENVSETUP_XDG_ENV" "$ENVSETUP_XDG_CACHE"; do
		[[ -e "$var" ]] || continue
		if envsetup::dry_run; then envsetup::would "delete $var"; else rm -rf "$var"; fi
	done
	envsetup::dry_run || rmdir "${ENVSETUP_XDG_CACHE%/*}" 2>/dev/null || true
	return "$failed"
}
