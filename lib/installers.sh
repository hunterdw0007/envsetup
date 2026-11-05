#!/usr/bin/env bash
# This file runs the installer scripts in ENVSETUP_INSTALLER_DIRS.
# Installers handle anything that a package manager cannot install.
# Each installer is a separate bash script that is safe to run more than once.

envsetup::run_installers() {
	local script scripts=() names=() failed=()
	if envsetup::lite; then
		gum style --foreground 3 "work (lite) does not assume sudo, so it runs no installers."
		return 0
	fi
	readarray -t scripts < <(envsetup::resolved_installers)
	names=("${scripts[@]##*/}")
	names=("${names[@]%.sh}")
	if ((${#scripts[@]} == 0)); then
		gum style --foreground 3 "No installers for $ENVSETUP_PROFILE."
		return 0
	fi
	if envsetup::dry_run; then
		envsetup::would "run ${#scripts[@]} installer scripts, and each one skips a tool that is already installed: ${names[*]}"
		return 0
	fi
	for script in "${scripts[@]}"; do
		gum style --bold --foreground 4 "Running ${script##*/}..."
		bash "$script" || failed+=("${script##*/}")
	done
	if ((${#failed[@]})); then
		gum style --foreground 1 "Installers failed: ${failed[*]}"
		return 1
	fi
}
