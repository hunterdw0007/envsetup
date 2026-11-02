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

# First, so it runs under the bash 3.2 that macOS ships, and before anything changes.
if [[ "$OSTYPE" == darwin* ]]; then
	cat >&2 <<'EOF'
envsetup supports Linux only.
v0.3.0 is the last release that supports macOS.
To install v0.3.0, run:

  curl -fsSL https://raw.githubusercontent.com/hunterdw0007/envsetup/v0.3.0/install.sh | ENVSETUP_VERSION=v0.3.0 bash

To uninstall envsetup, run:

  curl -fsSL https://raw.githubusercontent.com/hunterdw0007/envsetup/v0.3.0/install.sh | ENVSETUP_VERSION=v0.3.0 bash -s -- --uninstall
EOF
	exit 1
fi

REPO_URL="${ENVSETUP_REPO_URL:-https://github.com/hunterdw0007/envsetup.git}"
ENVSETUP_VERSION="${ENVSETUP_VERSION:-latest}"

# As root already (containers, WSL), via sudo, or via doas (Alpine).
envsetup::as_root() {
	if ((EUID == 0)); then
		"$@"
	elif command -v sudo &>/dev/null; then
		sudo "$@"
	elif command -v doas &>/dev/null; then
		doas "$@"
	else
		echo "Needs root, but there's no sudo or doas: $*" >&2
		return 1
	fi
}

envsetup::bootstrap_git() {
	command -v git &>/dev/null && return 0

	echo "git not found, attempting to install it..." >&2
	if command -v brew &>/dev/null; then
		brew install git
	elif command -v apt-get &>/dev/null; then
		# See envsetup::pkg_install: a single broken source fails update, not the install.
		envsetup::as_root apt-get update || echo "apt-get update reported errors; installing anyway." >&2
		envsetup::as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y git
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

envsetup::bootstrap_git

download=$(mktemp -d)
trap 'rm -rf "$download"' EXIT
# A signal (Ctrl-C, a closed terminal, kill) would otherwise end this without the EXIT trap.
trap 'exit 130' INT TERM HUP
git clone -q "$REPO_URL" "$download"
envsetup::use_version "$ENVSETUP_VERSION"
echo "Downloaded envsetup $(git -C "$download" describe --tags --always) to $download, which is deleted when setup ends."

# stdin from the terminal: under `curl ... | bash` it's the pipe from curl, which would
# starve setup.sh's interactive gum prompts. Not exec'd, so the traps above still run.
"$download/setup.sh" "$@" </dev/tty
