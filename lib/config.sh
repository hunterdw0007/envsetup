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
	ENVSETUP_SKIP=()
	if [[ "$ENVSETUP_PROFILE" == home ]]; then ENVSETUP_SHELL=zsh; else ENVSETUP_SHELL=bash; fi
	ENVSETUP_XDG_NINJA=0

	[[ -f "$ENVSETUP_USER_CONFIG" ]] || return 0
	# Every interactive shell sources this file too, so it may not be strict-mode
	# clean; don't let that abort setup.
	set +eu
	# shellcheck source=/dev/null # user-supplied file
	source "$ENVSETUP_USER_CONFIG"
	set -eu
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

# What "Run installers" would run, in order: every *.sh in ENVSETUP_INSTALLER_DIRS,
# minus ENVSETUP_SKIP (installer name = script name without .sh).
envsetup::resolved_installers() {
	local dir script name
	for dir in "${ENVSETUP_INSTALLER_DIRS[@]}"; do
		for script in "$dir"/*.sh; do
			[[ -f "$script" ]] || continue
			name=${script##*/}
			envsetup::skipped "${name%.sh}" || echo "$script"
		done
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
