# shellcheck shell=bash
# Shell functions loaded on every machine except work lite. Bash only (arrays), so zsh
# skips them. Bash 3.2-safe (no mapfile), since that's macOS's /bin/bash.

[[ -n "${BASH_VERSION:-}" ]] || return 0

# shellcheck source=/dev/null # sibling file, resolved at runtime
source "$ENVSETUP_ROOT/shell/shared/colors.sh"

if command -v gio >/dev/null; then
	trash() { gio trash "$@"; }
fi

# Prefixes piped lines with │, and the last one with └.
format_with_pipes() {
	local lines=() line i
	while IFS= read -r line || [[ -n "$line" ]]; do lines+=("$line"); done
	for i in "${!lines[@]}"; do
		if ((i + 1 == ${#lines[@]})); then echo "└ ${lines[i]}"; else echo "│ ${lines[i]}"; fi
	done
}

# _envsetup_tabulate <heading>...: ':'-separated lines on stdin, as aligned columns
# under those headings. util-linux's column (Linux) names them and truncates the last to
# fit; BSD's (macOS) can't name columns, so it gets a heading row instead.
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
# All of them work on the git repos directly under the current directory.
# ============================================================================

# Branch, ahead/behind, latest semver tag and branch description of every repo. The
# ahead/behind is ps1.sh's parse_git_tracking, which init.sh loads in every mode.
branchAll() {
	local output
	output=$(
		for dir in ./*/; do
			[[ -d "$dir/.git" ]] || continue
			repo_name=$(basename "$dir")
			branch_name=$(git -C "$dir" rev-parse --abbrev-ref HEAD)
			branch_info=$(parse_git_tracking "$dir")
			branch_info=${branch_info# }
			branch_tag=$(git -C "$dir" tag -l --sort=-version:refname | grep -E '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$' | head -n 1)
			branch_description=$(git -C "$dir" config branch."${branch_name}".description)
			echo -e "${BOLD}$repo_name:${RESET}${BOLD_BLUE}$branch_name${RESET} ${BOLD_RED}$branch_info${RESET}:${BOLD_YELLOW}$branch_tag${RESET}:$branch_description"
		done
	)
	# The trailing newline matters: BSD column drops a last line without one.
	printf "%s\n" "$output" | _envsetup_tabulate Repository Tracking "Latest Tag" Description
}

fetchAll() {
	local quiet=false output_file="" arg
	for arg in "$@"; do
		case $arg in
		--quiet)
			quiet=true
			output_file=$(mktemp /tmp/fetch_all.XXXXXX)
			;;
		--help)
			echo "Fetches all git repos located in the current directory"
			echo "Options:"
			echo "    --quiet - runs in the background and outputs to a temp file"
			echo "    --help  - prints this help message"
			return 0
			;;
		esac
	done

	if $quiet; then
		_fetch_all_repos >>"$output_file" &
		echo "🚛 Fetching repositories in the background. Output will be in $output_file"
	else
		_fetch_all_repos
		echo ""
		branchAll
	fi
}

_fetch_all_repos() {
	local dir
	for dir in ./*/; do
		[[ -d "$dir/.git" ]] || continue
		echo "🚛 Fetching $dir"
		git -C "$dir" fetch --force --prune --prune-tags 2>&1 | format_with_pipes
	done
}

# Pulls every repo that's on main/master and behind its remote.
pullMainAll() {
	local summary="" force=false arg dir
	for arg in "$@"; do
		case $arg in
		--force) force=true ;;
		--help)
			echo "Pulls all git repos that are behind their remote origin located in the current directory"
			echo "Options:"
			echo "    --force - pulls all repos regardless of whether they are behind or not"
			echo "    --help  - prints this help message"
			return 0
			;;
		esac
	done

	for dir in ./*/; do
		if [[ -d "$dir/.git" && "$(git -C "$dir" rev-parse --abbrev-ref HEAD)" =~ ^(main|master)$ ]]; then
			if $force || git -C "$dir" branch -v | grep -q "^\*.*\[.*behind [0-9]"; then
				echo "🚜 Pulling $(basename "$dir")"
				git -c color.ui=always -C "$dir" pull | format_with_pipes
				summary+="$(basename "$dir")"$'\n'
			fi
		fi
	done

	if [[ -n "$summary" ]]; then
		echo ""
		echo "Pulled the following directories:"
		printf "%s" "$summary"
	else
		echo "No directories were pulled."
	fi
	echo ""
	branchAll
}

# Sets every repo under $REPO (default: the current directory) to track origin/main.
mainOriginAll() {
	local dir
	for dir in "${REPO:-.}"/*/; do
		[[ -d "$dir/.git" ]] && git -C "$dir" branch --set-upstream-to=origin/main >/dev/null 2>&1
	done
	echo "⚓ All repositories set to track origin/main"
	branchAll
}

# pruneBranches [N] [--force] [--yes] [--dry-run]: deletes all but the N most recently
# committed local branches (default 5), after listing them and asking. main, master and
# the current branch always stay, and so do unmerged branches unless --force.
pruneBranches() {
	local keep=5 force=false yes=false dry=false current branch upstream reply arg count=0 failed=0
	local -a branches=() merged=() unmerged=()
	for arg; do
		case $arg in
		--force) force=true ;;
		--yes) yes=true ;;
		--dry-run) dry=true ;;
		--help)
			echo "Deletes all but the N most recently committed local branches (default 5), after"
			echo "listing them and asking. main, master and the current branch always stay."
			echo "Usage: pruneBranches [N] [--force] [--yes] [--dry-run]"
			echo "    --force   - also delete branches that aren't merged, losing their commits"
			echo "    --yes     - don't ask first"
			echo "    --dry-run - only list what it would delete"
			return 0
			;;
		'' | *[!0-9]*)
			echo "pruneBranches: unknown option: $arg (see --help)" >&2
			return 2
			;;
		*) keep=$arg ;;
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
		# Merged the way `git branch -d` means it: into its upstream, or into HEAD if none.
		upstream=$(git rev-parse -q --verify "$branch@{upstream}" 2>/dev/null) || upstream=HEAD
		if git merge-base --is-ancestor "$branch" "$upstream"; then merged+=("$branch"); else unmerged+=("$branch"); fi
	done
	if $force; then
		merged+=(${unmerged[@]+"${unmerged[@]}"})
	elif ((${#unmerged[@]})); then
		echo "Keeping ${#unmerged[@]} unmerged (--force deletes them too, with their commits):"
		printf '  %s\n' "${unmerged[@]}"
	fi
	if ((${#merged[@]} == 0)); then
		echo "Nothing to delete."
		return 0
	fi
	echo "Would delete ${#merged[@]}:"
	printf '  %s\n' "${merged[@]}"
	$dry && return 0
	if ! $yes; then
		read -r -p "Delete them? [y/N] " reply
		if [[ $reply != [yY]* ]]; then
			echo "Nothing deleted."
			return 0
		fi
	fi
	for branch in "${merged[@]}"; do
		if $force; then git branch -D "$branch"; else git branch -d "$branch"; fi || failed=1
	done
	return "$failed"
}

# pruneBranchesAll [pruneBranches options]: pruneBranches in every repo under the
# current directory, asking once per repo.
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
