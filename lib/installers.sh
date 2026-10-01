#!/usr/bin/env bash
# Runs the installer scripts in ENVSETUP_INSTALLER_DIRS: anything that isn't a plain
# package-manager package. Each is a standalone, idempotent bash script.

envsetup::run_installers() {
	local script scripts=() names=() failed=()
	if envsetup::lite; then
		gum style --foreground 3 "work (lite) assumes no sudo access, so installers are skipped."
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
		envsetup::would "run ${#scripts[@]} installer scripts, each a no-op if its tool is already there: ${names[*]}"
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
