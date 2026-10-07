#!/usr/bin/env bash
# Bootstraps envsetup on a new machine:
#
#   curl -fsSL https://raw.githubusercontent.com/hunterdw0007/envsetup/main/install.sh | bash
#
# Clones (or updates) the repo, checks out the newest release, then hands off into
# setup.sh's TUI. Arguments go to setup.sh, e.g. `... | bash -s -- --dry-run` to look
# around without changing anything beyond the clone. ENVSETUP_VERSION picks another
# release (v1.2.0 or 1.2.0), or a branch or commit.
set -euo pipefail

REPO_URL="${ENVSETUP_REPO_URL:-https://github.com/hunterdw0007/envsetup.git}"
ENVSETUP_DIR="${ENVSETUP_DIR:-$HOME/envsetup}"
ENVSETUP_VERSION="${ENVSETUP_VERSION:-latest}"

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

# Release tags (vX.Y.Z), newest first. Pre-releases (v1.2.0-rc.1) aren't listed.
envsetup::releases() {
	local tag
	while read -r tag; do
		if [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo "$tag"; fi
	done < <(git -C "$ENVSETUP_DIR" tag --list 'v*' --sort=-v:refname)
}

# use_version <version>: checks out "latest" (the newest release, or the default branch
# before the first one), a release (v1.2.0 or 1.2.0), or a branch or commit. Releases
# and commits are checked out detached; a branch is fast-forwarded to origin's.
envsetup::use_version() {
	local ref=$1 releases target branch='' file
	local git=(git -C "$ENVSETUP_DIR")
	if [[ "$ref" == latest ]]; then
		read -r ref < <(envsetup::releases) || true
		if [[ -z "$ref" ]]; then
			ref=$("${git[@]}" symbolic-ref -q --short refs/remotes/origin/HEAD || true)
			ref=${ref#origin/}
		fi
		if [[ -z "$ref" ]]; then
			echo "No releases yet, and no default branch to fall back to; staying on what's checked out."
			return 0
		fi
	fi
	if [[ "$ref" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then ref=v$ref; fi

	if "${git[@]}" show-ref -q --verify "refs/tags/$ref"; then
		target=refs/tags/$ref
	elif "${git[@]}" show-ref -q --verify "refs/remotes/origin/$ref"; then
		target=origin/$ref branch=$ref
	elif "${git[@]}" rev-parse -q --verify "$ref^{commit}" >/dev/null; then
		target=$ref
	else
		echo "envsetup has no release, branch or commit called \"$1\"." >&2
		releases=$(envsetup::releases)
		if [[ -n "$releases" ]]; then
			printf 'Releases, newest first:\n  %s\n' "${releases//$'\n'/$'\n'  }" >&2
		fi
		exit 1
	fi
	# Edits to tracked files would block switching, or be carried into another version.
	if [[ "$("${git[@]}" rev-parse HEAD)" != "$("${git[@]}" rev-parse "$target^{commit}")" ]] &&
		! "${git[@]}" diff --quiet HEAD; then
		echo "$ENVSETUP_DIR has local changes, so it can't switch to $1:" >&2
		while read -r file; do echo "  $file" >&2; done < <("${git[@]}" diff --name-only HEAD)
		echo "Your own settings belong in ~/.config/envsetup/config.sh (see the README), which" >&2
		echo "updates never touch. To set the changes aside: git -C $ENVSETUP_DIR stash" >&2
		exit 1
	fi

	if [[ -n "$branch" ]]; then
		"${git[@]}" show-ref -q --verify "refs/heads/$branch" || "${git[@]}" branch -q --track "$branch" "$target"
		"${git[@]}" checkout -q "$branch" --
		"${git[@]}" merge -q --ff-only "$target"
	else
		"${git[@]}" checkout -q --detach "$target"
	fi
}

envsetup::bootstrap_macos
envsetup::bootstrap_git

if [[ -d "$ENVSETUP_DIR/.git" ]]; then
	echo "Updating existing envsetup checkout at $ENVSETUP_DIR..."
	git -C "$ENVSETUP_DIR" fetch -q --tags origin
elif [[ -e "$ENVSETUP_DIR" ]]; then
	echo "$ENVSETUP_DIR already exists and isn't a git checkout. Set ENVSETUP_DIR to another path or remove it first." >&2
	exit 1
else
	echo "Cloning envsetup into $ENVSETUP_DIR..."
	git clone "$REPO_URL" "$ENVSETUP_DIR"
fi
envsetup::use_version "$ENVSETUP_VERSION"
echo "envsetup $(git -C "$ENVSETUP_DIR" describe --tags --always) is checked out at $ENVSETUP_DIR."

# Reopen stdin from the controlling terminal: when this script is run via
# `curl ... | bash`, stdin is the pipe from curl, not the terminal, which would
# otherwise starve setup.sh's interactive gum prompts.
exec "$ENVSETUP_DIR/setup.sh" "$@" </dev/tty
