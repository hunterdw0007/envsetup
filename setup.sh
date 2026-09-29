#!/usr/bin/env bash
# Entry point: gum-driven menu to link shell config and install packages.
set -euo pipefail

ENVSETUP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ENVSETUP_ROOT
source "$ENVSETUP_ROOT/lib/common.sh"
source "$ENVSETUP_ROOT/lib/config.sh"
source "$ENVSETUP_ROOT/lib/zsh.sh"
source "$ENVSETUP_ROOT/lib/installers.sh"
source "$ENVSETUP_ROOT/lib/git.sh"

CONFIG_DIR="$HOME/.config/envsetup"
PROFILE_FILE="$CONFIG_DIR/profile"
MODE_FILE="$CONFIG_DIR/mode"
RC_MARKER_BEGIN="# >>> envsetup >>>"
RC_MARKER_END="# <<< envsetup <<<"

envsetup::ensure_gum || exit 1

envsetup::current_profile() {
	if [[ -f "$PROFILE_FILE" ]]; then cat "$PROFILE_FILE"; fi
}

envsetup::set_profile() {
	mkdir -p "$CONFIG_DIR"
	echo "$1" >"$PROFILE_FILE"
}

# Mode only applies to the work profile: "lite" assumes no sudo access and
# skips package installs; "full" (the default) assumes sudo and does everything.
envsetup::current_mode() {
	[[ -f "$MODE_FILE" ]] && cat "$MODE_FILE" || echo full
}

envsetup::set_mode() {
	mkdir -p "$CONFIG_DIR"
	echo "$1" >"$MODE_FILE"
}

envsetup::clear_mode() {
	rm -f "$MODE_FILE"
}

envsetup::link_shell_config() {
	local rc_file
	if [[ "$ENVSETUP_SHELL" == zsh ]]; then
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
		# shellcheck disable=SC2016 # single-quoted on purpose: expands when the rc file sources it, not now
		echo '[ -f "$ENVSETUP_ROOT/shell/init.sh" ] && source "$ENVSETUP_ROOT/shell/init.sh"'
		echo "$RC_MARKER_END"
	} >>"$rc_file"

	gum style --foreground 2 "Linked shell config into $rc_file (restart your shell to pick it up)"
}

envsetup::install_packages_for_profile() {
	local profile=$1 manager
	if [[ "$profile" == work && "$(envsetup::current_mode)" == lite ]]; then
		gum style --foreground 3 "work (lite) assumes no sudo access, so package installs are skipped."
		return 0
	fi

	manager="$(envsetup::pkg_manager)"
	if [[ -z "$manager" ]]; then
		gum style --foreground 1 "No supported package manager found."
		return 1
	fi

	local pkg pkgs=()
	local -A seen=()
	for pkg in "${ENVSETUP_PACKAGES[@]}"; do
		[[ -z "$pkg" || -n "${seen[$pkg]:-}" ]] && continue
		seen[$pkg]=1
		envsetup::skipped "$pkg" || pkgs+=("$pkg")
	done

	if ((${#pkgs[@]} == 0)); then
		gum style --foreground 3 "No packages listed for $profile."
		return 0
	fi

	gum style --bold --foreground 4 "Installing via $manager: ${pkgs[*]}"
	envsetup::install_packages "$manager" "${pkgs[@]}"
}

envsetup::main_menu() {
	local profile label choice
	while true; do
		profile="$(envsetup::current_profile)"
		label="${profile:-none}"
		[[ "$profile" == work ]] && label+=" ($(envsetup::current_mode))"
		envsetup::load_config "$profile" "$(envsetup::current_mode)"
		choice="$(gum choose \
			"Select profile (current: $label)" \
			"Edit config" \
			"Link shell config" \
			"Configure git" \
			"Install packages" \
			"Run installers" \
			"Run everything" \
			"Quit")"

		case "$choice" in
		"Select profile"*)
			profile="$(gum choose work home)"
			envsetup::set_profile "$profile"
			if [[ "$profile" == work ]]; then
				envsetup::set_mode "$(gum choose lite full)"
			else
				envsetup::clear_mode
			fi
			;;
		"Edit config")
			envsetup::edit_config
			;;
		"Link shell config")
			envsetup::link_shell_config
			;;
		"Configure git")
			envsetup::setup_git
			;;
		"Install packages")
			[[ -z "$profile" ]] && { gum style --foreground 1 "Select a profile first."; continue; }
			envsetup::install_packages_for_profile "$profile"
			;;
		"Run installers")
			[[ -z "$profile" ]] && { gum style --foreground 1 "Select a profile first."; continue; }
			envsetup::run_installers "$profile"
			;;
		"Run everything")
			[[ -z "$profile" ]] && { gum style --foreground 1 "Select a profile first."; continue; }
			envsetup::link_shell_config
			envsetup::setup_git
			envsetup::install_packages_for_profile "$profile"
			envsetup::run_installers "$profile"
			;;
		"Quit" | "")
			break
			;;
		esac
	done
}

gum style --border rounded --padding "1 2" --bold "envsetup"
envsetup::main_menu
