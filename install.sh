#!/usr/bin/env bash
# Bootstraps envsetup on a new machine:
#
#   curl -fsSL https://raw.githubusercontent.com/hunterdw0007/envsetup/main/install.sh | bash
#
# Downloads the newest release to a temporary folder, runs setup.sh's menu from it, and
# deletes the folder when that ends, however it ends. "Link shell config" copies what new
# shells need out of it first. Arguments go to setup.sh, e.g. `... | bash -s -- --dry-run`
# to look around without changing anything. ENVSETUP_VERSION picks another release
# (v1.2.0 or 1.2.0), or a branch or commit.
set -euo pipefail

REPO_URL="${ENVSETUP_REPO_URL:-https://github.com/hunterdw0007/envsetup.git}"
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

# A copy of shell/shared/brew.sh, which isn't downloaded yet; keep the two in sync. Only
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
	done < <(git -C "$download" tag --list 'v*' --sort=-v:refname)
}

# use_version <version>: checks out "latest" (the newest release, or the default branch
# before the first one), a release (v1.2.0 or 1.2.0), or a branch or commit, detached.
envsetup::use_version() {
	local ref=$1 releases target
	local git=(git -C "$download")
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
		target=origin/$ref
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
	"${git[@]}" checkout -q --detach "$target"
}

envsetup::bootstrap_macos
envsetup::bootstrap_git

# A template, since macOS's mktemp -d alone ignores TMPDIR.
download=$(mktemp -d "${TMPDIR:-/tmp}/envsetup.XXXXXX")
trap 'rm -rf "$download"' EXIT
# A signal (Ctrl-C, a closed terminal, kill) would otherwise end this without the EXIT trap.
trap 'exit 130' INT TERM HUP
git clone -q "$REPO_URL" "$download"
envsetup::use_version "$ENVSETUP_VERSION"
echo "Downloaded envsetup $(git -C "$download" describe --tags --always) to $download, which is deleted when setup ends."

# stdin from the terminal: under `curl ... | bash` it's the pipe from curl, which would
# starve setup.sh's interactive gum prompts. Not exec'd, so the traps above still run.
"$download/setup.sh" "$@" </dev/tty
