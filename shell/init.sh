#!/usr/bin/env bash
# Sourced from your shell rc file (added by setup.sh). Loads shared config,
# then the config for the active profile (set via `setup.sh`).

[[ -n "${ENVSETUP_ROOT:-}" ]] || return 0

for f in "$ENVSETUP_ROOT"/shell/shared/*.sh; do
	[[ -f "$f" ]] && source "$f"
done

profile_file="$HOME/.config/envsetup/profile"
if [[ -f "$profile_file" ]]; then
	profile="$(<"$profile_file")"
	for f in "$ENVSETUP_ROOT/shell/profiles/$profile"/*.sh; do
		[[ -f "$f" ]] && source "$f"
	done
fi
