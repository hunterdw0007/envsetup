#!/usr/bin/env bash
# This file loads the settings that setup.sh acts on.
# It loads the repo's defaults first, then the user's config.sh.
# config.example.sh documents the settings.
# shellcheck disable=SC2034 # setup.sh, lib/*.sh and the user's config read the ENVSETUP_* variables

ENVSETUP_USER_CONFIG="$ENVSETUP_STATE/config.sh"
# The clone of the user's own config repo (see envsetup::sync_config_repo).
ENVSETUP_CONFIG_CLONE="$ENVSETUP_STATE/repo"

envsetup::load_config() {
	ENVSETUP_PROFILE=$1
	ENVSETUP_MODE=$2

	readarray -t ENVSETUP_PACKAGES < <(grep -hvE '^\s*(#|$)' \
		"$ENVSETUP_ROOT/packages/common.txt" "$ENVSETUP_ROOT/packages/$ENVSETUP_PROFILE.txt" 2>/dev/null)
	readarray -t ENVSETUP_GIT_CONFIG < <(git config --file "$ENVSETUP_ROOT/git/gitconfig" --list)
	ENVSETUP_INSTALLER_DIRS=("$ENVSETUP_ROOT/installers/common" "$ENVSETUP_ROOT/installers/$ENVSETUP_PROFILE")
	ENVSETUP_EXTRAS=()
	ENVSETUP_SKIP=()
	ENVSETUP_SHELL=bash
	ENVSETUP_XDG_NINJA=0

	[[ -f "$ENVSETUP_USER_CONFIG" ]] || return 0
	# Each interactive shell also sources config.sh.
	# So config.sh may not work under set -e or set -u.
	# This function loads config.sh with -e and -u off.
	# Afterwards, it turns the caller's options back on.
	# A syntax error or a failed command then gives one warning.
	# config.sh can see and change this function's local variables.
	# So the local names have a prefix.
	local _envsetup_opts=$- _envsetup_err='' _envsetup_line='' _envsetup_trap
	if ! _envsetup_err=$("$BASH" -n "$ENVSETUP_USER_CONFIG" 2>&1); then
		_envsetup_err=${_envsetup_err%%$'\n'*}
		_envsetup_err="${_envsetup_err#"$ENVSETUP_USER_CONFIG: "}"
	else
		_envsetup_err=
	fi
	_envsetup_trap=$(trap -p ERR)
	# Only a failed command in config.sh itself counts.
	# config.sh may end with a false `[[ ... ]] && ...`.
	# Then `source` below returns 1, but that is not an error.
	trap 'if [[ ${BASH_SOURCE[0]} == "$ENVSETUP_USER_CONFIG" ]]; then _envsetup_line=${_envsetup_line:-$LINENO}; fi' ERR
	set +eu
	# shellcheck source=/dev/null # the user's own file
	source "$ENVSETUP_USER_CONFIG"
	trap - ERR
	eval "$_envsetup_trap"
	if [[ $_envsetup_opts == *e* ]]; then set -e; fi
	if [[ $_envsetup_opts == *u* ]]; then set -u; fi
	if [[ -n "$_envsetup_err" ]]; then
		envsetup::config_warning "$ENVSETUP_USER_CONFIG did not load completely ($_envsetup_err). envsetup uses the settings before the error."
	elif [[ -n "$_envsetup_line" ]]; then
		envsetup::config_warning "In $ENVSETUP_USER_CONFIG, the command on line $_envsetup_line failed. envsetup continues with the other settings."
	fi
}

# config_warning <text> shows the text only once, until the text changes.
# The menu loads config.sh again each time it shows, so the same warning would repeat.
envsetup::config_warning() {
	if [[ "$1" != "${ENVSETUP_CONFIG_WARNED:-}" ]]; then
		ENVSETUP_CONFIG_WARNED=$1
		gum style --foreground 3 "$1" >&2
	fi
}

# work lite does not assume sudo, so it runs no packages and no installers.
envsetup::lite() { [[ "$ENVSETUP_PROFILE" == work && "$ENVSETUP_MODE" == lite ]]; }

envsetup::skipped() {
	[[ " ${ENVSETUP_SKIP[*]:-} " == *" $1 "* ]]
}

# resolved_packages prints what "Install packages" installs.
# That is ENVSETUP_PACKAGES without duplicates and without ENVSETUP_SKIP.
# Descriptions and previews of packages use this function too.
# So they always match what runs.
envsetup::resolved_packages() {
	local pkg
	local -A seen=()
	for pkg in "${ENVSETUP_PACKAGES[@]}"; do
		[[ -z "$pkg" || -n "${seen[$pkg]:-}" ]] && continue
		seen[$pkg]=1
		envsetup::skipped "$pkg" || echo "$pkg"
	done
}

# resolved_installers prints what "Run installers" runs, in order.
# First come all *.sh files in ENVSETUP_INSTALLER_DIRS.
# Then come the installers/extras/ scripts that ENVSETUP_EXTRAS names.
# It leaves out ENVSETUP_SKIP.
# An installer's name is its script name without .sh.
envsetup::resolved_installers() {
	local dir script name scripts=()
	for dir in "${ENVSETUP_INSTALLER_DIRS[@]}"; do
		scripts+=("$dir"/*.sh)
	done
	for name in "${ENVSETUP_EXTRAS[@]}"; do
		script=$ENVSETUP_ROOT/installers/extras/$name.sh
		if [[ -f "$script" ]]; then
			scripts+=("$script")
		else
			echo "ENVSETUP_EXTRAS: no installer for \"$name\" (see installers/extras/)" >&2
		fi
	done
	for script in "${scripts[@]}"; do
		[[ -f "$script" ]] || continue
		name=${script##*/}
		envsetup::skipped "${name%.sh}" || echo "$script"
	done
}

# sync_config_repo gets config.sh from the user's own git repo.
# The first run clones ENVSETUP_CONFIG_REPO into ENVSETUP_CONFIG_CLONE.
# Setting ENVSETUP_CONFIG_REPO is the user's choice to clone.
# Later runs ask before they pull the clone.
# They do not need ENVSETUP_CONFIG_REPO.
# Then config.sh becomes a symlink to the config.sh in the clone.
# The function asks before it replaces a config.sh of the user's own.
# It moves that file to config.sh.bak first.
# If the user keeps their own config.sh, later runs neither ask nor pull.
# A failed clone or pull shows a warning.
# The menu still opens.
envsetup::sync_config_repo() {
	local url=${ENVSETUP_CONFIG_REPO:-} repo=$ENVSETUP_CONFIG_CLONE link=$ENVSETUP_STATE/config.sh origin rc=0
	if [[ -n "$url" ]]; then
		# The short form "me" means github.com/me/envsetup-config.
		if [[ "$url" != */* && "$url" != *:* ]]; then url=github.com/$url/envsetup-config; fi
		# The short form "me/dotfiles" means github.com/me/dotfiles.
		if [[ "$url" =~ ^[^/:.]+/[^/:]+$ ]]; then url=github.com/$url; fi
		# A URL without a scheme, such as github.com/me/dotfiles, uses https.
		if [[ "$url" != *:* && "$url" != /* ]]; then url=https://$url; fi
	fi
	if [[ -d "$repo/.git" ]]; then
		origin=$(git -C "$repo" remote get-url origin 2>/dev/null) || origin=
		if [[ -n "$url" && "$url" != "$origin" ]]; then
			gum style --foreground 3 "ENVSETUP_CONFIG_REPO is $url, but $repo comes from ${origin:-an unknown URL}. envsetup keeps using $repo."
		fi
		# The user kept their own config.sh, so the clone does not matter to this run.
		if [[ (-e "$link" || -L "$link") && "$(readlink "$link")" != "$repo/config.sh" ]]; then return 0; fi
		if envsetup::dry_run; then
			envsetup::would "ask to pull $repo"
		elif gum confirm "Pull your config repo ($repo) before the menu opens?"; then
			if ! git -C "$repo" pull -q --ff-only; then
				gum style --foreground 3 "Couldn't pull $repo. Commit and push your edits there, or undo them. envsetup uses the config.sh that it has."
			fi
		fi
	elif [[ -n "$url" ]]; then
		if envsetup::dry_run; then
			envsetup::would "clone $url into $repo"
			envsetup::would "link $link to $repo/config.sh"
			return 0
		fi
		if ! git clone -q -- "$url" "$repo"; then
			gum style --foreground 3 "Couldn't clone $url. Check ENVSETUP_CONFIG_REPO, then run setup again. The menu opens without your repo."
			return 0
		fi
		gum style --foreground 2 "Cloned $url into $repo"
	else
		return 0
	fi

	if [[ ! -f "$repo/config.sh" ]]; then
		gum style --foreground 3 "$repo has no config.sh, so envsetup links none."
		return 0
	fi
	if [[ -L "$link" && "$(readlink "$link")" == "$repo/config.sh" ]]; then return 0; fi
	# Only a run that just cloned gets here with a config.sh of the user's own, so this is never a dry run.
	if [[ -e "$link" || -L "$link" ]]; then
		# Only a clear no (exit 1) replaces the file. Ctrl-C keeps it.
		gum confirm "Keep your own $link? No moves it to $link.bak and links $repo/config.sh instead." || rc=$?
		if ((rc != 1)); then return 0; fi
		if [[ -e "$link.bak" || -L "$link.bak" ]]; then
			gum style --foreground 3 "$link.bak already exists, so envsetup keeps $link as it is."
			return 0
		fi
		mv "$link" "$link.bak"
		gum style --foreground 2 "Moved your old config.sh to $link.bak"
	fi
	if envsetup::dry_run; then
		envsetup::would "link $link to $repo/config.sh"
		return 0
	fi
	ln -sfn "$repo/config.sh" "$link"
	gum style --foreground 2 "Linked $link to $repo/config.sh"
}

envsetup::edit_config() {
	# A link to a file that is gone would make cp below write into the clone.
	if [[ -L "$ENVSETUP_USER_CONFIG" && ! -e "$ENVSETUP_USER_CONFIG" ]]; then
		gum style --foreground 3 "$ENVSETUP_USER_CONFIG linked to a file that is gone. Edit config replaces the link with a new config.sh."
		rm -f "$ENVSETUP_USER_CONFIG"
	fi
	if [[ ! -f "$ENVSETUP_USER_CONFIG" ]]; then
		mkdir -p "${ENVSETUP_USER_CONFIG%/*}"
		cp "$ENVSETUP_ROOT/config.example.sh" "$ENVSETUP_USER_CONFIG"
	fi
	if [[ -L "$ENVSETUP_USER_CONFIG" ]]; then
		gum style --foreground 3 "This config.sh is in your config repo. Commit and push your edits there, or a later pull fails."
	fi
	local editor
	read -ra editor <<<"${EDITOR:-vi}"
	"${editor[@]}" "$ENVSETUP_USER_CONFIG"
}
