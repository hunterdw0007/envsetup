#!/usr/bin/env bash
# Entry point: gum-driven menu to link shell config and install packages.
set -euo pipefail

ENVSETUP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ENVSETUP_ROOT/lib/common.sh"
source "$ENVSETUP_ROOT/lib/zsh.sh"

CONFIG_DIR="$HOME/.config/envsetup"
PROFILE_FILE="$CONFIG_DIR/profile"
RC_MARKER_BEGIN="# >>> envsetup >>>"
RC_MARKER_END="# <<< envsetup <<<"

envsetup::ensure_gum || exit 1

envsetup::current_profile() {
	[[ -f "$PROFILE_FILE" ]] && cat "$PROFILE_FILE"
}

envsetup::set_profile() {
	mkdir -p "$CONFIG_DIR"
	echo "$1" >"$PROFILE_FILE"
}

envsetup::link_shell_config() {
	local profile rc_file
	profile="$(envsetup::current_profile)"

	if [[ "$profile" == home ]]; then
		envsetup::setup_zsh || return 1
		rc_file="$HOME/.zshrc"
	else
		rc_file="$HOME/.bashrc"
	fi

	if [[ -f "$rc_file" ]] && grep -qF "$RC_MARKER_BEGIN" "$rc_file"; then
		gum style --foreground 3 "Already linked in $rc_file"
		return 0
	fi

	{
		echo "$RC_MARKER_BEGIN"
		echo "export ENVSETUP_ROOT=\"$ENVSETUP_ROOT\""
		echo '[ -f "$ENVSETUP_ROOT/shell/init.sh" ] && source "$ENVSETUP_ROOT/shell/init.sh"'
		echo "$RC_MARKER_END"
	} >>"$rc_file"

	gum style --foreground 2 "Linked shell config into $rc_file (restart your shell to pick it up)"
}

envsetup::install_packages_for_profile() {
	local profile=$1 manager
	manager="$(envsetup::pkg_manager)"
	if [[ -z "$manager" ]]; then
		gum style --foreground 1 "No supported package manager found."
		return 1
	fi

	local pkgs=()
	readarray -t pkgs < <(cat "$ENVSETUP_ROOT/packages/common.txt" "$ENVSETUP_ROOT/packages/$profile.txt" 2>/dev/null |
		grep -vE '^\s*(#|$)' | sort -u)

	if ((${#pkgs[@]} == 0)); then
		gum style --foreground 3 "No packages listed for $profile."
		return 0
	fi

	gum style --bold --foreground 4 "Installing via $manager: ${pkgs[*]}"
	envsetup::install_packages "$manager" "${pkgs[@]}"
}

envsetup::main_menu() {
	local profile choice
	while true; do
		profile="$(envsetup::current_profile)"
		choice="$(gum choose \
			"Select profile (current: ${profile:-none})" \
			"Link shell config" \
			"Install packages" \
			"Link + install" \
			"Quit")"

		case "$choice" in
		"Select profile"*)
			profile="$(gum choose work home)"
			envsetup::set_profile "$profile"
			;;
		"Link shell config")
			envsetup::link_shell_config
			;;
		"Install packages")
			[[ -z "$profile" ]] && { gum style --foreground 1 "Select a profile first."; continue; }
			envsetup::install_packages_for_profile "$profile"
			;;
		"Link + install")
			[[ -z "$profile" ]] && { gum style --foreground 1 "Select a profile first."; continue; }
			envsetup::link_shell_config
			envsetup::install_packages_for_profile "$profile"
			;;
		"Quit" | "")
			break
			;;
		esac
	done
}

gum style --border rounded --padding "1 2" --bold "envsetup"
envsetup::main_menu
