# shellcheck shell=bash
# Shell functions loaded on every machine except work lite. Bash only (arrays,
# mapfile), so zsh, home's default shell, skips them.

[[ -n "${BASH_VERSION:-}" ]] || return 0

# shellcheck source=/dev/null # sibling file, resolved at runtime
source "$ENVSETUP_ROOT/shell/shared/colors.sh"

if command -v gio >/dev/null; then
	trash() { gio trash "$@"; }
fi

# Prefixes piped lines with │, and the last one with └.
format_with_pipes() {
	local lines=() i
	mapfile -t lines
	for i in "${!lines[@]}"; do
		if ((i + 1 == ${#lines[@]})); then echo "└ ${lines[i]}"; else echo "│ ${lines[i]}"; fi
	done
}

# ============================================================================
# GIT REPOSITORY MANAGEMENT FUNCTIONS
# All of them work on the git repos directly under the current directory.
# ============================================================================

# Branch, ahead/behind, latest semver tag and branch description of every repo.
branchAll() {
	local output
	output=$(
		for dir in ./*/; do
			[[ -d "$dir/.git" ]] || continue
			repo_name=$(basename "$dir")
			branch_name=$(git -C "$dir" rev-parse --abbrev-ref HEAD)
			branch_info=$(git -C "$dir" status -sb | grep -oP '(?<=\[)(?=.*(?:ahead|behind))[^\]]*(?=\])' | sed -e 's/behind/⤺/g ; s/ahead/⤻/g')
			[[ -n "$branch_info" ]] && branch_info="[$branch_info]"
			branch_tag=$(git -C "$dir" tag -l --sort=-version:refname | grep -E '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$' | head -n 1)
			branch_description=$(git -C "$dir" config branch."${branch_name}".description)
			echo -e "${BOLD}$repo_name:${RESET}${BOLD_BLUE}$branch_name${RESET} ${BOLD_RED}$branch_info${RESET}:${BOLD_YELLOW}$branch_tag${RESET}:$branch_description"
		done
	)
	printf "%s" "$output" | column -t -s ':' -C name=Repository -C name=Tracking -C name="Latest Tag" -C name=Description,trunc
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
		printf "%s" "$summary" | column -t -N "Pulled the following directories:"
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

# Deletes (-D) all but the N most recently committed local branches (default 5);
# main, master and the current branch are always kept.
pruneBranches() {
	local keep=${1:-5} current branch count=0
	local -a branches
	git rev-parse --is-inside-work-tree &>/dev/null || {
		echo "Not a git repo: $PWD" >&2
		return 1
	}
	current=$(git symbolic-ref --short HEAD 2>/dev/null)
	mapfile -t branches < <(git for-each-ref --sort=-committerdate refs/heads/ --format='%(refname:short)')
	for branch in "${branches[@]}"; do
		[[ $branch == main || $branch == master || $branch == "$current" ]] && continue
		((++count > keep)) && git branch -D "$branch"
	done
	return 0
}

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
