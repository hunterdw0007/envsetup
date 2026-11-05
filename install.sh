#!/usr/bin/env bash
# install.sh starts envsetup on a new machine:
#
#   curl -fsSL https://raw.githubusercontent.com/hunterdw0007/envsetup/main/install.sh | bash
#
# It downloads the newest release to a temporary folder.
# It runs the setup.sh menu from that folder.
# When the menu ends, in any way, it deletes the folder.
# Before that, "Link shell config" copies what new shells need out of the folder.
# Arguments go to setup.sh.
# For example, `... | bash -s -- --dry-run` opens the menu without changing anything.
# ENVSETUP_VERSION selects another release (v1.2.0 or 1.2.0), or a branch or commit.
set -euo pipefail

# This check runs first, so the old bash 3.2 on a Mac can parse it.
# On a Mac, nothing changes.
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

# as_root runs a command as root.
# If the user is already root, it runs the command directly (containers, WSL).
# Otherwise it uses sudo, or doas (Alpine).
envsetup::as_root() {
	if ((EUID == 0)); then
		"$@"
	elif command -v sudo &>/dev/null; then
		sudo "$@"
	elif command -v doas &>/dev/null; then
		doas "$@"
	else
		echo "This command needs root, but this machine has no sudo or doas: $*" >&2
		return 1
	fi
}

envsetup::bootstrap_git() {
	command -v git &>/dev/null && return 0

	echo "git is not installed. Installing git..." >&2
	if command -v brew &>/dev/null; then
		brew install git
	elif command -v apt-get &>/dev/null; then
		# One broken source fails the update, but not the install (see envsetup::pkg_install).
		envsetup::as_root apt-get update || echo "apt-get update reported errors. Installing anyway." >&2
		envsetup::as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y git
	elif command -v dnf &>/dev/null; then
		envsetup::as_root dnf install -y git
	elif command -v zypper &>/dev/null; then
		envsetup::as_root zypper --non-interactive install git
	elif command -v pacman &>/dev/null; then
		# A new container has never synced.
		# The sync uses -u, because Arch does not support partial upgrades.
		compgen -G '/var/lib/pacman/sync/*.db' >/dev/null || envsetup::as_root pacman -Syu --noconfirm
		envsetup::as_root pacman -S --noconfirm --needed git
	elif command -v apk &>/dev/null; then
		envsetup::as_root apk add git
	elif command -v nix-env &>/dev/null; then
		nix-env -f '<nixpkgs>' -iA git
	else
		echo "Couldn't install git. Install git yourself, then run this script again." >&2
		exit 1
	fi
}

# releases prints the release tags (vX.Y.Z), newest first.
# It leaves out test releases such as v1.2.0-rc.1.
envsetup::releases() {
	local tag
	while read -r tag; do
		if [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo "$tag"; fi
	done < <(git -C "$download" tag --list 'v*' --sort=-v:refname)
}

# use_version <version> checks out a version, detached from any branch.
# The version can be a release (v1.2.0 or 1.2.0), a branch or a commit.
# "latest" means the newest release.
# Before the first release, "latest" means the default branch.
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
			echo "envsetup has no releases and no default branch yet. Using the checked-out commit."
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
# A signal (Ctrl-C, a closed terminal, kill) would otherwise skip the EXIT trap.
trap 'exit 130' INT TERM HUP
git clone -q "$REPO_URL" "$download"
envsetup::use_version "$ENVSETUP_VERSION"
echo "Downloaded envsetup $(git -C "$download" describe --tags --always) to $download. envsetup deletes this folder when setup ends."

# setup.sh reads from the terminal.
# Under `curl ... | bash`, stdin is the pipe from curl.
# gum's questions in setup.sh would then get no input.
# This line does not use exec, so the traps above still run.
"$download/setup.sh" "$@" </dev/tty
