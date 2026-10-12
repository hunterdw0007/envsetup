# shellcheck shell=bash
# Prompt loaded on every machine, regardless of profile/mode:
#
#   [14:02:11] <kube context> ~/d/envsetup main [⤻ 1]
#   ❯
#
# Bash only: zsh uses different prompt escapes, and there the oh-my-zsh theme owns the
# prompt. PS1 isn't exported, so it doesn't leak into shells that can't read it.
#
# _envsetup_prompt runs from PROMPT_COMMAND and sets the variables PS1 shows. Only the
# ahead/behind count runs a program (one git call, inside a repo): the path, branch and
# kube context are read in bash.

[[ -n "${BASH_VERSION:-}" ]] || return 0

# ~/dev/envsetup -> ~/d/envsetup; dot-directories keep two characters (~/.c/envsetup).
_envsetup_prompt_dir() {
	# bash 3.2 keeps the backslash of a literal \~ in the replacement.
	local IFS=/ i tilde='~'
	local -a parts
	read -ra parts <<<"${PWD/#$HOME/$tilde}"
	_envsetup_prompt_dir=
	for ((i = 0; i < ${#parts[@]} - 1; i++)); do
		if [[ "${parts[i]}" == .* ]]; then _envsetup_prompt_dir+="${parts[i]:0:2}/"; else _envsetup_prompt_dir+="${parts[i]:0:1}/"; fi
	done
	_envsetup_prompt_dir+="${parts[${#parts[@]} - 1]}"
	_envsetup_prompt_dir=${_envsetup_prompt_dir:-/}
}

# The branch (or short commit, when detached) of the repo $PWD is in, from its HEAD file.
_envsetup_prompt_branch() {
	local dir=$PWD git head
	_envsetup_prompt_branch=
	until [[ -e "$dir/.git" ]]; do
		[[ -n "$dir" ]] || return 0
		dir=${dir%/*}
	done
	git=$dir/.git
	# Worktrees and submodules: .git is a file naming the real git dir.
	if [[ -f "$git" ]]; then
		read -r head <"$git" || true
		git=${head#gitdir: }
		[[ "$git" == /* ]] || git=$dir/$git
	fi
	read -r head <"$git/HEAD" 2>/dev/null || return 0
	if [[ "$head" == "ref: refs/heads/"* ]]; then
		_envsetup_prompt_branch=${head#ref: refs/heads/}
	else
		_envsetup_prompt_branch=${head:0:7}
	fi
	# A reftable repo's HEAD file is a placeholder.
	if [[ "$_envsetup_prompt_branch" == .invalid ]]; then
		_envsetup_prompt_branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
	fi
}

# _envsetup_prompt_tracking <repo>: " [⤻ ahead, ⤺ behind]" against the upstream, if either
# isn't 0 (also used by branchAll).
_envsetup_prompt_tracking() {
	local behind ahead
	_envsetup_prompt_tracking=
	read -r behind ahead < <(git -C "$1" rev-list --left-right --count '@{u}...HEAD' 2>/dev/null) || return 0
	((ahead)) && _envsetup_prompt_tracking="⤻ $ahead"
	((behind)) && _envsetup_prompt_tracking+="${_envsetup_prompt_tracking:+, }⤺ $behind"
	if [[ -n "$_envsetup_prompt_tracking" ]]; then _envsetup_prompt_tracking=" [$_envsetup_prompt_tracking]"; fi
}

# kubectl's current context: the first kubeconfig file that sets one. kubectl writes it
# after every cluster, so a big kubeconfig is read again only when it changes: the cache
# holds the files it's for and the context, and stays current while it's strictly newer
# than each of them (a same-second change, at bash 3.2's whole-second mtimes, reads again).
_envsetup_prompt_context() {
	local IFS=: file line key='' cached value fresh=true cache=${XDG_CACHE_HOME:-$HOME/.cache}/envsetup/kube-context
	local -a files=()
	_envsetup_prompt_context=
	read -ra files <<<"${KUBECONFIG:-$HOME/.kube/config}"
	for file in ${files[@]+"${files[@]}"}; do
		if [[ -r "$file" ]]; then key+="$file:"; fi
	done
	[[ -n "$key" ]] || return 0
	if { IFS= read -r cached && IFS= read -r value; } 2>/dev/null <"$cache" && [[ "$cached" == "$key" ]]; then
		for file in "${files[@]}"; do
			if [[ -r "$file" && ! "$cache" -nt "$file" ]]; then fresh=false; fi
		done
		if $fresh; then
			_envsetup_prompt_context=$value
			return 0
		fi
	fi
	for file in "${files[@]}"; do
		[[ -r "$file" ]] || continue
		while IFS= read -r line; do
			if [[ "$line" =~ ^current-context:[[:space:]]*[\"\']?([^\"\'[:space:]]+) ]]; then
				_envsetup_prompt_context="${BASH_REMATCH[1]} "
				break 2
			fi
		done <"$file"
	done
	[[ -d "${cache%/*}" ]] || mkdir -p "${cache%/*}" 2>/dev/null
	printf '%s\n%s\n' "$key" "$_envsetup_prompt_context" 2>/dev/null >"$cache"
}

_envsetup_prompt() {
	local status=$?
	_envsetup_prompt_dir
	_envsetup_prompt_context
	_envsetup_prompt_branch
	_envsetup_prompt_git=
	if [[ -n "$_envsetup_prompt_branch" ]]; then
		_envsetup_prompt_tracking "$PWD"
		_envsetup_prompt_git=" $_envsetup_prompt_branch$_envsetup_prompt_tracking"
	fi
	return "$status"
}

# Newline-separated, since an existing PROMPT_COMMAND may end in ';'.
[[ "${PROMPT_COMMAND:-}" == *_envsetup_prompt* ]] || PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND$'\n'}_envsetup_prompt"
# shellcheck disable=SC2016 # single-quoted on purpose: expanded at every prompt
PS1='\[\033[0;96m\][\t]\[\033[0;95m\] ${_envsetup_prompt_context}\[\033[0;92m\]${_envsetup_prompt_dir}\[\033[0;94m\]${_envsetup_prompt_git}\n\[\033[0;93m\]❯ \[\033[0m\]'
