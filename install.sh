#!/usr/bin/env bash
# Bootstraps envsetup on a new machine:
#
#   curl -fsSL https://raw.githubusercontent.com/hunterdw0007/envsetup/main/install.sh | bash
#
# Clones (or updates) the repo, then hands off into setup.sh's TUI. Arguments go to
# setup.sh, e.g. `... | bash -s -- --dry-run` to look around without changing anything
# beyond the clone. See README.md for how to run this while the repo is still private.
set -euo pipefail

REPO_URL="${ENVSETUP_REPO_URL:-https://github.com/hunterdw0007/envsetup.git}"
ENVSETUP_DIR="${ENVSETUP_DIR:-$HOME/envsetup}"

# As root already (containers, WSL), via sudo, or via doas (Alpine).
envsetup::as_root() {
	if ((EUID == 0)); then "$@"; elif command -v sudo &>/dev/null; then sudo "$@"; else doas "$@"; fi
}

# macOS: git comes with Apple's Command Line Tools, and the rest from Homebrew, including
# a newer bash than the 3.2 macOS ships (setup.sh needs 4+). This file runs under that
# 3.2 (`curl | bash`), so it stays bash 3.2-safe.
envsetup::bootstrap_macos() {
	local reply installer
	[[ "$OSTYPE" == darwin* ]] || return 0
	if ! xcode-select -p &>/dev/null; then
		xcode-select --install || true # opens Apple's installer dialog
		echo "Install Apple's Command Line Tools from the dialog that just opened (they include git), then run this again." >&2
		exit 1
	fi
	envsetup::brew_shellenv
	if ! command -v brew &>/dev/null; then
		reply=
		read -rp "envsetup installs everything with Homebrew, which isn't installed. Install it now (https://brew.sh, asks for your password)? [y/N] " reply </dev/tty || true
		if [[ "$reply" != [yY]* ]]; then
			echo "Install Homebrew from https://brew.sh, then run this again." >&2
			exit 1
		fi
		# Homebrew's documented install. It has no published checksum to verify: it's the
		# script at HEAD, so it's only as trusted as Homebrew's repo. Downloaded first:
		# `bash -c "$(curl ...)"` would run an empty script, and "succeed", if the
		# download failed.
		installer=$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)
		/bin/bash -c "$installer" </dev/tty
		envsetup::brew_shellenv
	fi
	if ! "$(brew --prefix)/bin/bash" -c '((BASH_VERSINFO[0] >= 4))' 2>/dev/null; then
		echo "Installing a current bash with Homebrew (macOS ships 3.2)..." >&2
		brew install bash
	fi
}

# A copy of shell/shared/brew.sh, which isn't cloned yet; keep the two in sync. Only
# called on macOS.
envsetup::brew_shellenv() {
	local brew
	command -v brew &>/dev/null && return 0
	for brew in /opt/homebrew/bin/brew /usr/local/bin/brew; do
		if [[ -x "$brew" ]]; then
			eval "$("$brew" shellenv)"
			return 0
		fi
	done
}

envsetup::bootstrap_git() {
	command -v git &>/dev/null && return 0

	echo "git not found, attempting to install it..." >&2
	if command -v brew &>/dev/null; then
		brew install git
	elif command -v apt-get &>/dev/null; then
		# See envsetup::pkg_install: a single broken source fails update, not the install.
		envsetup::as_root apt-get update || echo "apt-get update reported errors; installing anyway." >&2
		envsetup::as_root apt-get install -y git
	elif command -v dnf &>/dev/null; then
		envsetup::as_root dnf install -y git
	elif command -v zypper &>/dev/null; then
		envsetup::as_root zypper --non-interactive install git
	elif command -v pacman &>/dev/null; then
		# Never synced (a fresh container): sync with -u, since Arch doesn't do partial upgrades.
		compgen -G '/var/lib/pacman/sync/*.db' >/dev/null || envsetup::as_root pacman -Syu --noconfirm
		envsetup::as_root pacman -S --noconfirm --needed git
	elif command -v apk &>/dev/null; then
		envsetup::as_root apk add git
	elif command -v nix-env &>/dev/null; then
		nix-env -f '<nixpkgs>' -iA git
	else
		echo "Could not auto-install git. Install it manually, then re-run this script." >&2
		exit 1
	fi
}

envsetup::bootstrap_macos
envsetup::bootstrap_git

if [[ -d "$ENVSETUP_DIR/.git" ]]; then
	echo "Updating existing envsetup checkout at $ENVSETUP_DIR..."
	git -C "$ENVSETUP_DIR" pull --ff-only
elif [[ -e "$ENVSETUP_DIR" ]]; then
	echo "$ENVSETUP_DIR already exists and isn't a git checkout. Set ENVSETUP_DIR to another path or remove it first." >&2
	exit 1
else
	echo "Cloning envsetup into $ENVSETUP_DIR..."
	git clone "$REPO_URL" "$ENVSETUP_DIR"
fi

# Reopen stdin from the controlling terminal: when this script is run via
# `curl ... | bash`, stdin is the pipe from curl, not the terminal, which would
# otherwise starve setup.sh's interactive gum prompts.
exec "$ENVSETUP_DIR/setup.sh" "$@" </dev/tty
