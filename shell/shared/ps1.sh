# shellcheck shell=bash
# Prompt loaded on every machine, regardless of profile/mode:
#
#   [14:02:11] <kube context> ~/d/envsetup main [⤻ 1]
#   ❯
#
# On a day listed in your ~/.config/envsetup/holidays.txt or in holidays.txt next to
# this file (yours is checked first), ❯ becomes that day's emoji.
#
# Bash only: zsh uses different prompt escapes, and on home the oh-my-zsh theme owns
# the prompt. PS1 isn't exported, so it doesn't leak into shells that can't read it.

[[ -n "${BASH_VERSION:-}" ]] || return 0

# ~/dev/envsetup -> ~/d/envsetup; dot-directories keep two characters (~/.c/envsetup).
collapsed_directory() {
	local IFS=/ result="" i
	local -a parts
	read -ra parts <<<"${PWD/#$HOME/\~}"
	for ((i = 0; i < ${#parts[@]} - 1; i++)); do
		if [[ "${parts[i]}" == .* ]]; then result+="${parts[i]:0:2}/"; else result+="${parts[i]:0:1}/"; fi
	done
	result+="${parts[${#parts[@]} - 1]}"
	echo "${result:-/}"
}

parse_git_branch() {
	local branch
	branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
	if [[ -n "$branch" ]]; then echo " $branch"; fi
}

# [ahead N], [behind N] or both, with arrows instead of words.
parse_git_tracking() {
	local tracking
	tracking=$(git branch -v 2>/dev/null | grep "^\*" | grep -o "\[\(ahead \+[0-9]\+\(, behind \+[0-9]\+\)\?\|behind \+[0-9]\+\(, ahead \+[0-9]\+\)\?\)\]" | sed -e 's/behind/⤺/g ; s/ahead/⤻/g')
	if [[ -n "$tracking" ]]; then echo " $tracking"; fi
}

get_current_context() {
	if command -v kubectl >/dev/null; then kubectl config current-context 2>/dev/null; fi
}

get_holiday() {
	local quiet=false arg file line month day weekday
	for arg in "$@"; do
		case $arg in
		--quiet) quiet=true ;;
		--help)
			echo "Checks today's date against a list of holidays and prints a message and modifies the prompt character"
			echo "Options:"
			echo "    --quiet - only modifies the PROMPT_CHAR variable"
			echo "    --help  - prints this help message"
			return 0
			;;
		esac
	done

	read -r month day weekday < <(date '+%m %d %u') # weekday: 1 = Monday
	for file in "$HOME/.config/envsetup/holidays.txt" "${ENVSETUP_ROOT:-}/shell/shared/holidays.txt"; do
		[[ -f "$file" ]] || continue
		# `|| [[ -n $line ]]` still reads a last line with no trailing newline.
		while IFS= read -r line || [[ -n "$line" ]]; do
			[[ "$line" == fixed\ * || "$line" == floating\ * ]] || continue
			eval "set -- $line" # fields are shell words, so a quoted message stays one field
			if [[ $1 == fixed && $2 == "$month" && $3 == "$day" ]]; then
				set -- "$4" "$5"
			elif [[ $1 == floating && $2 == "$month" && $5 == "$weekday" ]] && ((10#$day >= 10#$3 && 10#$day <= 10#$4)); then
				set -- "$6" "$7"
			else
				continue
			fi
			PROMPT_CHAR=$2
			$quiet || printf '%s %s' "$1" "$2"
			return 0
		done <"$file"
	done
	$quiet || printf 'Happy %s' "$(date +%A)"
}

PROMPT_CHAR=❯
get_holiday --quiet

# shellcheck disable=SC2016 # single-quoted on purpose: the $(...) run at every prompt
PS1='\[\033[0;96m\][\t]\[\033[0;95m\] $(get_current_context) \[\033[0;92m\]$(collapsed_directory)\[\033[0;94m\]$(parse_git_branch)$(parse_git_tracking)\n\[\033[0;93m\]$PROMPT_CHAR \[\033[0m\]'
