#!/usr/bin/env bash
# This file loads the settings that envsetup acts on.
# It loads the repo's defaults first, then the user's config.sh.
# config.sh is bash, so the Go code runs these functions in bash (internal/setup/config.go).
# config.example.sh documents the settings.
# shellcheck disable=SC2034 # internal/setup/config.go and the user's config read the ENVSETUP_* variables

ENVSETUP_USER_CONFIG="$ENVSETUP_STATE/config.sh"
# The clone of the user's own config repo (see SyncConfigRepo in internal/setup/configedit.go).
ENVSETUP_CONFIG_CLONE="$ENVSETUP_STATE/repo"
# ENVSETUP_RENAMED lists the settings that got a new name.
# Each item is "<old name>=<new name>", for example "ENVSETUP_OLD=ENVSETUP_NEW".
# load_config still reads each old name.
# MigrateConfig (internal/setup/configedit.go) asks to write the new name into config.sh.
# With an item here, a rename is not a breaking change (see docs/interface.md).
ENVSETUP_RENAMED=()

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
	# Each old name from ENVSETUP_RENAMED starts with the new name's default.
	# So `OLD+=(x)` adds to the default, and a value from an earlier load is gone.
	local _envsetup_item _envsetup_old
	local -A _envsetup_before=()
	for _envsetup_item in "${ENVSETUP_RENAMED[@]}"; do
		_envsetup_old=${_envsetup_item%%=*}
		envsetup::copy_var "${_envsetup_item#*=}" "$_envsetup_old"
		_envsetup_before[$_envsetup_old]=$(declare -p "$_envsetup_old" 2>/dev/null)
	done
	trap 'if [[ ${BASH_SOURCE[0]} == "$ENVSETUP_USER_CONFIG" ]]; then _envsetup_line=${_envsetup_line:-$LINENO}; fi' ERR
	set +eu
	# shellcheck source=/dev/null # the user's own file
	source "$ENVSETUP_USER_CONFIG"
	trap - ERR
	eval "$_envsetup_trap"
	if [[ $_envsetup_opts == *e* ]]; then set -e; fi
	if [[ $_envsetup_opts == *u* ]]; then set -u; fi
	# An old name that config.sh changed sets the new name.
	# So a config.sh that the user did not migrate still works.
	# If config.sh changes both names, the old name wins.
	for _envsetup_item in "${ENVSETUP_RENAMED[@]}"; do
		_envsetup_old=${_envsetup_item%%=*}
		if [[ "$(declare -p "$_envsetup_old" 2>/dev/null)" != "${_envsetup_before[$_envsetup_old]}" ]]; then
			envsetup::copy_var "$_envsetup_old" "${_envsetup_item#*=}"
		fi
	done
	if [[ -n "$_envsetup_err" ]]; then
		envsetup::config_warning "$ENVSETUP_USER_CONFIG did not load completely ($_envsetup_err). envsetup uses the settings before the error."
	elif [[ -n "$_envsetup_line" ]]; then
		envsetup::config_warning "In $ENVSETUP_USER_CONFIG, the command on line $_envsetup_line failed. envsetup continues with the other settings."
	fi
}

# copy_var <from> <to> sets the variable <to> to the value of <from>.
# An array stays an array, and a plain value stays a plain value.
# If <from> is not set, it unsets <to>.
envsetup::copy_var() {
	local -n _envsetup_from=$1 _envsetup_to=$2
	unset _envsetup_to
	if [[ "$(declare -p "$1" 2>/dev/null)" =~ ^declare\ -[a-zA-Z]*a ]]; then
		_envsetup_to=("${_envsetup_from[@]}")
	elif [[ -v "$1" ]]; then
		# shellcheck disable=SC2178 # this branch copies a plain value, and the branch above copies an array
		_envsetup_to=$_envsetup_from
	fi
}

# config_warning <text> shows the text only once, until the text changes.
# The menu loads config.sh again each time it shows, so the same warning would repeat.
envsetup::config_warning() {
	if [[ "$1" != "${ENVSETUP_CONFIG_WARNED:-}" ]]; then
		ENVSETUP_CONFIG_WARNED=$1
		printf '%s\n' "$1" >&2
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

# settings_of reports these settings, and Go shows the ones that changed.
# Each item is "<label>:<variable name without ENVSETUP_>".
ENVSETUP_SETTINGS=(Packages:PACKAGES Extras:EXTRAS Skip:SKIP Shell:SHELL "XDG ninja:XDG_NINJA"
	"Git config:GIT_CONFIG" "Installer dirs:INSTALLER_DIRS")

# settings_of <file> loads the settings with that file as config.sh.
# It prints one "<label>|<value>" line for each value.
# It runs in a subshell, so the menu's own settings stay the same.
# A config.sh that runs exit ends the subshell early, so settings_of then prints nothing.
envsetup::settings_of() {
	(
		ENVSETUP_USER_CONFIG=$1
		envsetup::load_config "${ENVSETUP_PROFILE:-}" "${ENVSETUP_MODE:-full}" >/dev/null 2>&1
		for setting in "${ENVSETUP_SETTINGS[@]}"; do
			var="ENVSETUP_${setting#*:}[@]"
			for value in "${!var}"; do printf '%s|%s\n' "${setting%%:*}" "$value"; done
		done
	) || true # an exit 1 in config.sh must not end the caller under set -e
}
