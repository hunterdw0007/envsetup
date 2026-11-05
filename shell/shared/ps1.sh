# shellcheck shell=bash
# Every machine loads this prompt, in every profile and mode:
#
#   [14:02:11] <kube context> ~/d/envsetup main [⤻ 1]
#   ❯
#
# The prompt works only in bash.
# zsh uses different prompt escapes, and in zsh the oh-my-zsh theme sets the prompt.
# PS1 is not exported, so shells that cannot read it do not get it.
#
# _envsetup_prompt runs from PROMPT_COMMAND and sets the variables that PS1 shows.
# Only the ahead and behind count runs a program: one git command, inside a repo.
# bash itself reads the path, the branch and the Kubernetes context.

[[ -n "${BASH_VERSION:-}" ]] || return 0

# This function shortens ~/dev/envsetup to ~/d/envsetup.
# Folders that start with a dot keep two characters (~/.c/envsetup).
_envsetup_prompt_dir() {
	# The ~ is in a variable.
	# So no bash version keeps a backslash or expands the ~ in the replacement.
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

# This function reads the branch of the repo that $PWD is in, from its HEAD file.
# When HEAD is detached, it reads the short commit instead.
_envsetup_prompt_branch() {
	local dir=$PWD git head
	_envsetup_prompt_branch=
	until [[ -e "$dir/.git" ]]; do
		[[ -n "$dir" ]] || return 0
		dir=${dir%/*}
	done
	git=$dir/.git
	# In worktrees and submodules, .git is a file that names the real git folder.
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
	# In a repo with the reftable format, the HEAD file holds no real branch.
	if [[ "$_envsetup_prompt_branch" == .invalid ]]; then
		_envsetup_prompt_branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
	fi
}

# _envsetup_prompt_tracking <repo> sets " [⤻ ahead, ⤺ behind]", compared with the upstream.
# It sets the text only if either count is not 0.
# branchAll also uses this function.
_envsetup_prompt_tracking() {
	local behind ahead
	_envsetup_prompt_tracking=
	read -r behind ahead < <(git -C "$1" rev-list --left-right --count '@{u}...HEAD' 2>/dev/null) || return 0
	((ahead)) && _envsetup_prompt_tracking="⤻ $ahead"
	((behind)) && _envsetup_prompt_tracking+="${_envsetup_prompt_tracking:+, }⤺ $behind"
	if [[ -n "$_envsetup_prompt_tracking" ]]; then _envsetup_prompt_tracking=" [$_envsetup_prompt_tracking]"; fi
}

# This function reads kubectl's current context from the first kubeconfig file that sets one.
# kubectl adds every cluster to the kubeconfig, so the file can get big.
# So the function reads the kubeconfig again only when it changes.
# The cache file holds the context and the names of the kubeconfig files.
# The cache stays valid while it is newer than each of those files.
# A change in the same second as the cache counts as a change.
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

# A newline separates the commands, because an existing PROMPT_COMMAND may end in ';'.
[[ "${PROMPT_COMMAND:-}" == *_envsetup_prompt* ]] || PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND$'\n'}_envsetup_prompt"
# shellcheck disable=SC2016 # single quotes on purpose, so it expands at every prompt
PS1='\[\033[0;96m\][\t]\[\033[0;95m\] ${_envsetup_prompt_context}\[\033[0;92m\]${_envsetup_prompt_dir}\[\033[0;94m\]${_envsetup_prompt_git}\n\[\033[0;93m\]❯ \[\033[0m\]'
