# shellcheck shell=bash
# Every machine loads these shell functions, work lite too.
# They use bash arrays, so they work only in bash, and zsh skips them.

[[ -n "${BASH_VERSION:-}" ]] || return 0

# shellcheck source=/dev/null # a file in the same folder, found at runtime
source "$ENVSETUP_ROOT/shell/shared/colors.sh"

if command -v gio >/dev/null; then
	trash() { gio trash "$@"; }
fi

# This function puts │ before each line from stdin, and └ before the last line.
_envsetup_format_with_pipes() {
	local lines=() line i
	while IFS= read -r line || [[ -n "$line" ]]; do lines+=("$line"); done
	for i in "${!lines[@]}"; do
		if ((i + 1 == ${#lines[@]})); then echo "└ ${lines[i]}"; else echo "│ ${lines[i]}"; fi
	done
}

# _envsetup_tabulate <heading>... prints lines from stdin as aligned columns under those headings.
# The fields on each line are separated by ':'.
# A newer column from util-linux names the columns and shortens the last one to fit.
# An older column cannot name columns, so the function prints a heading row instead.
_envsetup_tabulate() {
	local args=() heading
	if column -C name=x </dev/null >/dev/null 2>&1; then
		for heading; do args+=(-C "name=$heading"); done
		args[${#args[@]} - 1]+=,trunc
		column -t -s ':' "${args[@]}"
	else
		{
			local IFS=:
			echo "$*"
			cat
		} | column -t -s ':'
	fi
}

# ============================================================================
# GIT REPOSITORY MANAGEMENT FUNCTIONS
# Each function works on the git repos directly under the current folder.
# ============================================================================

# branchAll prints each repo's branch, its commits ahead and behind, its newest version tag and its branch description.
# The ahead and behind counts come from _envsetup_prompt_tracking in ps1.sh.
# init.sh loads ps1.sh in every mode.
branchAll() {
	local output dir repo_name branch_name branch_info branch_tag branch_description
	local b='' blue='' red='' yellow='' r=''
	# branchAll uses its own colors, because your shell can change the colors in colors.sh.
	# It uses no color when NO_COLOR is set (https://no-color.org).
	# It also uses no color when the output is not a terminal.
	if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
		b=$'\033[1m' blue=$'\033[1;34m' red=$'\033[1;31m' yellow=$'\033[1;33m' r=$'\033[0m'
	fi
	output=$(
		for dir in ./*/; do
			[[ -d "$dir/.git" ]] || continue
			repo_name=${dir%/}
			repo_name=${repo_name##*/}
			branch_name=$(git -C "$dir" rev-parse --abbrev-ref HEAD)
			_envsetup_prompt_tracking "$dir"
			# shellcheck disable=SC2154 # _envsetup_prompt_tracking in ps1.sh sets this
			branch_info=${_envsetup_prompt_tracking# }
			branch_tag=$(git -C "$dir" tag -l --sort=-version:refname | grep -E '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$' | head -n 1)
			branch_description=$(git -C "$dir" config branch."${branch_name}".description)
			printf '%s\n' "$b$repo_name:$r$blue$branch_name$r $red$branch_info$r:$yellow$branch_tag$r:$branch_description"
		done
	)
	printf "%s\n" "$output" | _envsetup_tabulate Repository Tracking "Latest Tag" Description
}

# fetchAll [--quiet] fetches each repo, then lists the repos that it could not fetch.
# It returns 1 if one or more fetches failed.
fetchAll() {
	local quiet=false arg log status=0
	for arg in "$@"; do
		case $arg in
		--quiet) quiet=true ;;
		--help)
			echo "Fetches every git repo in the current folder"
			echo "Options:"
			echo "    --quiet - runs in the background and writes the output to a log file"
			echo "    --help  - prints this help message"
			return 0
			;;
		esac
	done

	if $quiet; then
		# Each run writes the same log again, so old logs do not pile up.
		# Uninstall removes the log.
		log=${XDG_CACHE_HOME:-$HOME/.cache}/envsetup/fetchAll.log
		mkdir -p "${log%/*}" || return 1
		_envsetup_fetch_all_repos >"$log" 2>&1 &
		echo "🚛 Fetching repositories in the background. The output goes to $log"
	else
		_envsetup_fetch_all_repos || status=1
		echo ""
		branchAll
		return "$status"
	fi
}

_envsetup_fetch_all_repos() {
	local dir failed=''
	for dir in ./*/; do
		[[ -d "$dir/.git" ]] || continue
		echo "🚛 Fetching $dir"
		git -C "$dir" fetch --force --prune 2>&1 | _envsetup_format_with_pipes
		# Use the status of git, not of the formatter at the end of the pipe.
		if ((PIPESTATUS[0] != 0)); then failed+=" $dir"; fi
	done
	if [[ -n "$failed" ]]; then
		echo "Could not fetch:$failed"
		return 1
	fi
	echo "Fetched all repositories."
}

# pullMainAll pulls every repo that is on main or master and behind its remote.
pullMainAll() {
	local summary="" failed="" force=false arg dir name
	for arg in "$@"; do
		case $arg in
		--force) force=true ;;
		--help)
			echo "Pulls every git repo in the current folder that is behind its origin remote"
			echo "Options:"
			echo "    --force - pulls every repo, also the ones that are not behind"
			echo "    --help  - prints this help message"
			return 0
			;;
		esac
	done

	for dir in ./*/; do
		if [[ -d "$dir/.git" && "$(git -C "$dir" rev-parse --abbrev-ref HEAD)" =~ ^(main|master)$ ]]; then
			if $force || git -C "$dir" branch -v | grep -q "^\*.*\[.*behind [0-9]"; then
				name=${dir%/}
				name=${name##*/}
				echo "🚜 Pulling $name"
				git -c color.ui=always -C "$dir" pull 2>&1 | _envsetup_format_with_pipes
				# Use the status of git, not of the formatter at the end of the pipe.
				if ((PIPESTATUS[0] == 0)); then summary+="$name"$'\n'; else failed+="$name"$'\n'; fi
			fi
		fi
	done

	if [[ -n "$summary" ]]; then
		echo ""
		echo "Pulled these folders:"
		printf "%s" "$summary"
	fi
	if [[ -n "$failed" ]]; then
		echo ""
		echo "Could not pull these folders:"
		printf "%s" "$failed"
	fi
	if [[ -z "$summary$failed" ]]; then echo "Pulled no folders."; fi
	echo ""
	branchAll
	if [[ -n "$failed" ]]; then return 1; fi
}

# mainOriginAll [dir] sets each repo under dir to track origin/main.
# The default dir is the current folder.
# It lists the repos that it could not set, and returns 1 if one or more failed.
mainOriginAll() {
	local root=${1:-.} dir name failed=0
	if [[ "$root" == --help ]]; then
		echo "Sets every git repo in a folder to track origin/main. The default folder is the current one."
		echo "Usage: mainOriginAll [dir]"
		return 0
	fi
	for dir in "$root"/*/; do
		[[ -d "$dir/.git" ]] || continue
		name=${dir%/}
		name=${name##*/}
		if git -C "$dir" branch --set-upstream-to=origin/main >/dev/null 2>&1; then
			echo "⚓ $name tracks origin/main"
		else
			echo "✗ $name: could not track origin/main (no origin remote, or no main branch on it)"
			failed=1
		fi
	done
	echo ""
	(cd "$root" && branchAll)
	return "$failed"
}

# pruneBranches [N] [--force] [--yes] [--dry-run] keeps the N local branches with the newest commits.
# It deletes the other local branches, after it lists them and asks.
# The default N is 5.
# main, master and the current branch always stay.
# Unmerged branches also stay, unless you add --force.
pruneBranches() {
	local keep=5 force=false yes=false dry=false current branch upstream reply arg count=0 failed=0
	local -a branches=() merged=() unmerged=()
	for arg; do
		case $arg in
		--force) force=true ;;
		--yes) yes=true ;;
		--dry-run) dry=true ;;
		--help)
			echo "Keeps the N local branches with the newest commits (default 5)."
			echo "Lists the other local branches, asks, then deletes them."
			echo "main, master and the current branch always stay."
			echo "Usage: pruneBranches [N] [--force] [--yes] [--dry-run]"
			echo "    --force   - also delete unmerged branches, and lose their commits"
			echo "    --yes     - do not ask first"
			echo "    --dry-run - only list the branches to delete"
			return 0
			;;
		'' | *[!0-9]*)
			echo "pruneBranches: unknown option: $arg (see --help)" >&2
			return 2
			;;
		*) keep=$((10#$arg)) ;;
		esac
	done
	git rev-parse --is-inside-work-tree &>/dev/null || {
		echo "Not a git repo: $PWD" >&2
		return 1
	}
	current=$(git symbolic-ref --short HEAD 2>/dev/null)
	while IFS= read -r branch; do branches+=("$branch"); done < <(git for-each-ref --sort=-committerdate refs/heads/ --format='%(refname:short)')
	for branch in "${branches[@]}"; do
		[[ $branch == main || $branch == master || $branch == "$current" ]] && continue
		((++count > keep)) || continue
		# Merged means what it means to `git branch -d`.
		# The branch is merged into its upstream, or into HEAD if it has no upstream.
		upstream=$(git rev-parse -q --verify "$branch@{upstream}" 2>/dev/null) || upstream=HEAD
		if git merge-base --is-ancestor "$branch" "$upstream"; then merged+=("$branch"); else unmerged+=("$branch"); fi
	done
	if ! $force && ((${#unmerged[@]})); then
		echo "Keeping ${#unmerged[@]} unmerged branches. --force deletes them too, with their commits:"
		printf '  %s\n' "${unmerged[@]}"
		unmerged=()
	fi
	if ((${#merged[@]} + ${#unmerged[@]} == 0)); then
		echo "Nothing to delete."
		return 0
	fi
	if ((${#merged[@]})); then
		echo "Would delete ${#merged[@]}:"
		printf '  %s\n' "${merged[@]}"
	fi
	if ((${#unmerged[@]})); then
		echo "Would delete ${#unmerged[@]} unmerged, with their commits:"
		printf '  %s\n' "${unmerged[@]}"
	fi
	$dry && return 0
	if ! $yes; then
		read -r -p "Delete them? [y/N] " reply
		if [[ $reply != [yY]* ]]; then
			echo "Nothing deleted."
			return 0
		fi
	fi
	for branch in ${merged[@]+"${merged[@]}"}; do git branch -d "$branch" || failed=1; done
	for branch in ${unmerged[@]+"${unmerged[@]}"}; do git branch -D "$branch" || failed=1; done
	return "$failed"
}

# pruneBranchesAll [pruneBranches options] runs pruneBranches in every repo under the current folder.
# It asks once for each repo.
pruneBranchesAll() {
	local dir
	for dir in */; do
		git -C "$dir" rev-parse --is-inside-work-tree &>/dev/null || continue
		echo "==> ${dir%/}"
		(cd "$dir" && pruneBranches "$@")
	done
}

alias ba='branchAll'
alias fa='fetchAll'
alias pma='pullMainAll'
alias pb='pruneBranches'
alias pba='pruneBranchesAll'
