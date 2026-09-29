#!/usr/bin/env bash
# Shared helpers for envsetup scripts.

# Dry run (--dry-run, or "Preview everything"): every step that would change the
# machine checks this first and describes the change instead of making it.
envsetup::dry_run() { [[ "${ENVSETUP_DRY_RUN:-0}" == 1 ]]; }
envsetup::would() { gum style --foreground 6 "  would $*"; }

envsetup::has_cmd() {
	command -v "$1" &>/dev/null
}

envsetup::pkg_manager() {
	if envsetup::has_cmd brew; then
		echo brew
	elif envsetup::has_cmd apt-get; then
		echo apt
	elif envsetup::has_cmd dnf; then
		echo dnf
	elif envsetup::has_cmd pacman; then
		echo pacman
	fi
}

envsetup::ensure_gum() {
	envsetup::has_cmd gum && return 0

	echo "gum not found, attempting to install it..." >&2
	if envsetup::has_cmd brew; then
		brew install gum
	elif envsetup::has_cmd go; then
		go install github.com/charmbracelet/gum@latest
		local gopath
		gopath="$(go env GOPATH)"
		export PATH="$gopath/bin:$PATH"
	else
		echo "Could not auto-install gum. See https://github.com/charmbracelet/gum#installation" >&2
		return 1
	fi

	envsetup::has_cmd gum
}

envsetup::install_packages() {
	local manager=$1
	shift
	local pkgs=("$@")
	((${#pkgs[@]} == 0)) && return 0

	case "$manager" in
	brew) brew install "${pkgs[@]}" ;;
	apt)
		# One broken source (e.g. a dead PPA) makes update exit non-zero even though the
		# rest refreshed; install anyway; it still fails loudly if the lists are unusable.
		sudo apt-get update || echo "apt-get update reported errors; installing anyway." >&2
		sudo apt-get install -y "${pkgs[@]}"
		;;
	dnf) sudo dnf install -y "${pkgs[@]}" ;;
	pacman) sudo pacman -S --noconfirm "${pkgs[@]}" ;;
	*)
		echo "No supported package manager found." >&2
		return 1
		;;
	esac
}
