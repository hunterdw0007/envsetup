#!/usr/bin/env bash
# Runs the third-party/custom installer scripts under installers/common and
# installers/<profile>, mirroring how shell/shared + shell/profiles work for
# shell config. Each script is a standalone, idempotent install step (a
# vendor installer, a manual binary download, or any other custom setup) —
# anything that isn't a plain package-manager package belongs here.

envsetup::run_installers() {
	local profile=$1
	if [[ "$profile" == work && "$(envsetup::current_mode)" == lite ]]; then
		gum style --foreground 3 "work (lite) assumes no sudo access, so installers are skipped."
		return 0
	fi

	local scripts=()
	readarray -t scripts < <(find "$ENVSETUP_ROOT/installers/common" "$ENVSETUP_ROOT/installers/$profile" \
		-maxdepth 1 -name '*.sh' 2>/dev/null | sort)

	if ((${#scripts[@]} == 0)); then
		gum style --foreground 3 "No installers for $profile."
		return 0
	fi

	local script failed=()
	for script in "${scripts[@]}"; do
		gum style --bold --foreground 4 "Running $(basename "$script")..."
		bash "$script" || failed+=("$(basename "$script")")
	done

	if ((${#failed[@]} > 0)); then
		gum style --foreground 1 "Installers failed: ${failed[*]}"
		return 1
	fi
}
