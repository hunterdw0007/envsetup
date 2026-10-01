#!/usr/bin/env bash
# Sourced from your shell rc file (added by setup.sh). Loads shared config, then
# the config for the active profile (set via `setup.sh`), then your own
# ~/.config/envsetup/config.sh last so anything in it wins.

[[ -n "${ENVSETUP_ROOT:-}" ]] || return 0

ENVSETUP_PROFILE=""
[[ -f "$HOME/.config/envsetup/profile" ]] && ENVSETUP_PROFILE="$(<"$HOME/.config/envsetup/profile")"

# The work profile's "lite" mode assumes no sudo access, so it only gets a
# prompt and aliases; everything else (home, work/full) loads the full set.
ENVSETUP_MODE="full"
[[ "$ENVSETUP_PROFILE" == work && -f "$HOME/.config/envsetup/mode" ]] && ENVSETUP_MODE="$(<"$HOME/.config/envsetup/mode")"

if [[ "$ENVSETUP_MODE" == lite ]]; then
	_envsetup_files=(ps1 aliases)
else
	_envsetup_files=(ps1 aliases exports functions)
fi

for _envsetup_f in "${_envsetup_files[@]}"; do
	_envsetup_f="$ENVSETUP_ROOT/shell/shared/$_envsetup_f.sh"
	# shellcheck disable=SC1090 # dynamic by design: the whole point is to source whatever's dropped here
	[[ -f "$_envsetup_f" ]] && source "$_envsetup_f"
done

# Exports for dotfiles "Move dotfiles to XDG dirs" moved (lib/xdg.sh); every mode needs
# them, or the programs would recreate the files in $HOME.
# shellcheck source=/dev/null # generated file
[[ -f "$HOME/.config/envsetup/xdg.sh" ]] && source "$HOME/.config/envsetup/xdg.sh"

if [[ -n "$ENVSETUP_PROFILE" ]]; then
	for _envsetup_f in "$ENVSETUP_ROOT/shell/profiles/$ENVSETUP_PROFILE"/*.sh; do
		# shellcheck disable=SC1090
		[[ -f "$_envsetup_f" ]] && source "$_envsetup_f"
	done
fi

# shellcheck source=/dev/null # user-supplied file
[[ -f "$HOME/.config/envsetup/config.sh" ]] && source "$HOME/.config/envsetup/config.sh"

unset _envsetup_files _envsetup_f
