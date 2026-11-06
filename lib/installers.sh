#!/usr/bin/env bash
# This file runs the installer scripts in ENVSETUP_INSTALLER_DIRS.
# Installers handle anything that a package manager cannot install.
# Each installer is a separate bash script that is safe to run more than once.

envsetup::run_installers() {
	local script name had pin scripts=() names=() failed=() updates=()
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
	# An update replaces a tool that envsetup installed at another version than the pin.
	# Your own installers have no pin, so they have no updates.
	for name in "${names[@]}"; do
		had=$(envsetup::installed_version "$name")
		pin=$(envsetup::pin "$name" 2>/dev/null) || continue
		if [[ -n "$had" && "$had" != "$pin" ]]; then updates+=("$name $had → $pin"); fi
	done
	if envsetup::dry_run; then
		envsetup::would "run ${#scripts[@]} installer scripts, and each one skips a tool that is already installed: ${names[*]}"
		for name in "${updates[@]}"; do envsetup::would "update $name"; done
		return 0
	fi
	if ((${#updates[@]})); then gum style --foreground 6 "Updates:" "${updates[@]/#/  }"; fi
	for script in "${scripts[@]}"; do
		gum style --bold --foreground 4 "Running ${script##*/}..."
		bash "$script" || failed+=("${script##*/}")
	done
	if ((${#failed[@]})); then
		gum style --foreground 1 "Installers failed: ${failed[*]}"
		return 1
	fi
}
