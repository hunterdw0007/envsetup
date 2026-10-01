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
