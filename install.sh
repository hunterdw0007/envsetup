#!/usr/bin/env bash
# Bootstraps envsetup on a new machine:
#
#   curl -fsSL https://raw.githubusercontent.com/hunterdw0007/envsetup/main/install.sh | bash
#
# Clones (or updates) the repo, then hands off into setup.sh's TUI. See README.md
# for how to run this while the repo is still private.
set -euo pipefail

REPO_URL="${ENVSETUP_REPO_URL:-https://github.com/hunterdw0007/envsetup.git}"
ENVSETUP_DIR="${ENVSETUP_DIR:-$HOME/envsetup}"

envsetup::bootstrap_git() {
	command -v git &>/dev/null && return 0

	echo "git not found, attempting to install it..." >&2
	if command -v apt-get &>/dev/null; then
		sudo apt-get update && sudo apt-get install -y git
	elif command -v dnf &>/dev/null; then
		sudo dnf install -y git
	elif command -v pacman &>/dev/null; then
		sudo pacman -S --noconfirm git
	elif command -v brew &>/dev/null; then
		brew install git
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
exec "$ENVSETUP_DIR/setup.sh" </dev/tty
