# shellcheck shell=bash
# Prompt loaded on every machine, regardless of profile/mode:
#
#   [14:02:11] <kube context> ~/d/envsetup main [⤻ 1]
#   ❯
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

# shellcheck disable=SC2016 # single-quoted on purpose: the $(...) run at every prompt
PS1='\[\033[0;96m\][\t]\[\033[0;95m\] $(get_current_context) \[\033[0;92m\]$(collapsed_directory)\[\033[0;94m\]$(parse_git_branch)$(parse_git_tracking)\n\[\033[0;93m\]❯ \[\033[0m\]'
