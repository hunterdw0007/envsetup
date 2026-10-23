#!/usr/bin/env bash
# What setup.sh acts on: the repo's defaults, then the user's config.sh on top
# (documented in config.example.sh).
# shellcheck disable=SC2034 # the ENVSETUP_* vars are read by setup.sh, lib/*.sh and the user's config

ENVSETUP_USER_CONFIG="$ENVSETUP_STATE/config.sh"

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
	# Each interactive shell also sources config.sh, so it can fail under set -e or set -u.
	# Thus it loads with -e and -u off. After it, the options of the caller come back,
	# and a syntax error or a failed command gives one warning. The local names have a
	# prefix, because config.sh can see (and change) the local variables of this function.
	local _envsetup_opts=$- _envsetup_err='' _envsetup_line='' _envsetup_trap
	if ! _envsetup_err=$("$BASH" -n "$ENVSETUP_USER_CONFIG" 2>&1); then
		_envsetup_err=${_envsetup_err%%$'\n'*}
		_envsetup_err="${_envsetup_err#"$ENVSETUP_USER_CONFIG: "}"
	else
		_envsetup_err=
	fi
	_envsetup_trap=$(trap -p ERR)
	# Only a command in config.sh itself counts: when its last command is a false
	# `[[ ... ]] && ...`, `source` below returns 1, and that is no error.
	trap 'if [[ ${BASH_SOURCE[0]} == "$ENVSETUP_USER_CONFIG" ]]; then _envsetup_line=${_envsetup_line:-$LINENO}; fi' ERR
	set +eu
	# shellcheck source=/dev/null # user-supplied file
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

# config_warning <text>: shows the text once, until the text changes (the menu loads
# config.sh again each time that it shows).
envsetup::config_warning() {
	if [[ "$1" != "${ENVSETUP_CONFIG_WARNED:-}" ]]; then
		ENVSETUP_CONFIG_WARNED=$1
		gum style --foreground 3 "$1" >&2
	fi
}

# work lite assumes no sudo: no packages, no installers.
envsetup::lite() { [[ "$ENVSETUP_PROFILE" == work && "$ENVSETUP_MODE" == lite ]]; }

envsetup::skipped() {
	[[ " ${ENVSETUP_SKIP[*]:-} " == *" $1 "* ]]
}

# What "Install packages" would install: ENVSETUP_PACKAGES deduped, minus
# ENVSETUP_SKIP. Anything that describes or previews packages uses this too, so
# it can't drift from what actually runs.
envsetup::resolved_packages() {
	local pkg
	local -A seen=()
	for pkg in "${ENVSETUP_PACKAGES[@]}"; do
		[[ -z "$pkg" || -n "${seen[$pkg]:-}" ]] && continue
		seen[$pkg]=1
		envsetup::skipped "$pkg" || echo "$pkg"
	done
}

# What "Run installers" would run, in order: every *.sh in ENVSETUP_INSTALLER_DIRS, then
# the opt-in installers/extras/ named in ENVSETUP_EXTRAS, minus ENVSETUP_SKIP (installer
# name = script name without .sh).
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

envsetup::edit_config() {
	if [[ ! -f "$ENVSETUP_USER_CONFIG" ]]; then
		mkdir -p "${ENVSETUP_USER_CONFIG%/*}"
		cp "$ENVSETUP_ROOT/config.example.sh" "$ENVSETUP_USER_CONFIG"
	fi
	local editor
	read -ra editor <<<"${EDITOR:-vi}"
	"${editor[@]}" "$ENVSETUP_USER_CONFIG"
}
