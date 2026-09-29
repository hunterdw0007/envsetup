#!/usr/bin/env bash
# Sourced from your shell rc file (added by setup.sh). Loads shared config,
# then the config for the active profile (set via `setup.sh`).

[[ -n "${ENVSETUP_ROOT:-}" ]] || return 0

profile_file="$HOME/.config/envsetup/profile"
mode_file="$HOME/.config/envsetup/mode"

profile=""
[[ -f "$profile_file" ]] && profile="$(<"$profile_file")"

# The work profile's "lite" mode assumes no sudo access, so it only gets a
# prompt and aliases; everything else (home, work/full) loads the full set.
mode="full"
[[ "$profile" == work && -f "$mode_file" ]] && mode="$(<"$mode_file")"

if [[ "$mode" == lite ]]; then
	components=(ps1 aliases)
else
	components=(ps1 aliases exports functions)
fi

for c in "${components[@]}"; do
	f="$ENVSETUP_ROOT/shell/shared/$c.sh"
	# shellcheck disable=SC1090 # dynamic by design: the whole point is to source whatever's dropped here
	[[ -f "$f" ]] && source "$f"
done

if [[ -n "$profile" ]]; then
	for f in "$ENVSETUP_ROOT/shell/profiles/$profile"/*.sh; do
		# shellcheck disable=SC1090
		[[ -f "$f" ]] && source "$f"
	done
fi
