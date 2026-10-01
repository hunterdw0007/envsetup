#!/usr/bin/env bash
# Shared helpers for envsetup scripts.
# shellcheck disable=SC2034 # the ENVSETUP_* constants are used by the other lib files

ENVSETUP_STATE="$HOME/.config/envsetup"
ENVSETUP_RC_BEGIN="# >>> envsetup >>>"
ENVSETUP_RC_END="# <<< envsetup <<<"

# Dry run (--dry-run, or "Preview everything"): every step that would change the
# machine checks this first and describes the change instead of making it.
envsetup::dry_run() { [[ "${ENVSETUP_DRY_RUN:-0}" == 1 ]]; }
envsetup::would() { gum style --foreground 6 "  would $*"; }
envsetup::has_cmd() { command -v "$1" &>/dev/null; }

envsetup::pkg_manager() {
	local cmd
	for cmd in brew apt-get dnf pacman; do
		if envsetup::has_cmd "$cmd"; then
			echo "${cmd%-get}"
			return 0
		fi
	done
}

envsetup::ensure_gum() {
	envsetup::has_cmd gum && return 0
	echo "gum not found, attempting to install it..." >&2
	if envsetup::has_cmd brew; then
		brew install gum
	elif envsetup::has_cmd go; then
		go install github.com/charmbracelet/gum@latest
		PATH="$(go env GOPATH)/bin:$PATH"
	else
		echo "Could not auto-install gum. See https://github.com/charmbracelet/gum#installation" >&2
		return 1
	fi
	envsetup::has_cmd gum
}

# pkg_install <manager> <package>...
envsetup::pkg_install() {
	local manager=$1 pkg failed=() install=()
	shift
	(($#)) || return 0
	case "$manager" in
	brew) install=(brew install) ;;
	apt)
		# One broken source (e.g. a dead PPA) makes update exit non-zero even though the
		# rest refreshed; install anyway; it still fails loudly if the lists are unusable.
		sudo apt-get update || echo "apt-get update reported errors; installing anyway." >&2
		install=(sudo apt-get install -y)
		;;
	dnf) install=(sudo dnf install -y) ;;
	pacman) install=(sudo pacman -S --noconfirm) ;;
	*)
		echo "No supported package manager found." >&2
		return 1
		;;
	esac
	# One at a time: in a batch, one package the system can't take (a conflict, a name
	# this distro doesn't use) fails all the others with it.
	for pkg; do
		"${install[@]}" "$pkg" || failed+=("$pkg")
	done
	((${#failed[@]} == 0)) && return 0
	echo "Couldn't install: ${failed[*]}" >&2
	return 1
}
