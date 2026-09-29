#!/usr/bin/env bash
# Runs the third-party/custom installer scripts in ENVSETUP_INSTALLER_DIRS
# (installers/common + installers/<profile> by default, plus any dirs the user's
# config.sh adds), mirroring how shell/shared + shell/profiles work for shell
# config. Each script is a standalone, idempotent install step (a vendor
# installer, a manual binary download, or any other custom setup) — anything
# that isn't a plain package-manager package belongs here.

envsetup::run_installers() {
	local profile=$1
	if [[ "$profile" == work && "$(envsetup::current_mode)" == lite ]]; then
		gum style --foreground 3 "work (lite) assumes no sudo access, so installers are skipped."
		return 0
	fi

	local dir script name scripts=()
	for dir in "${ENVSETUP_INSTALLER_DIRS[@]}"; do
		for script in "$dir"/*.sh; do
			[[ -f "$script" ]] || continue
			name=${script##*/}
			envsetup::skipped "${name%.sh}" || scripts+=("$script")
		done
	done

	if ((${#scripts[@]} == 0)); then
		gum style --foreground 3 "No installers for $profile."
		return 0
	fi

	local failed=()
	for script in "${scripts[@]}"; do
		name=${script##*/}
		gum style --bold --foreground 4 "Running $name..."
		bash "$script" || failed+=("$name")
	done

	if ((${#failed[@]} > 0)); then
		gum style --foreground 1 "Installers failed: ${failed[*]}"
		return 1
	fi
}
