#!/usr/bin/env bash
# Shared helpers for envsetup scripts.

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
	apt) sudo apt-get update && sudo apt-get install -y "${pkgs[@]}" ;;
	dnf) sudo dnf install -y "${pkgs[@]}" ;;
	pacman) sudo pacman -S --noconfirm "${pkgs[@]}" ;;
	*)
		echo "No supported package manager found." >&2
		return 1
		;;
	esac
}
