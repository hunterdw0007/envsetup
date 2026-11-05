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

# require_git stops with a hint when the machine has no git.
# It installs nothing, because the user has not chosen anything yet.
envsetup::require_git() {
	command -v git &>/dev/null && return 0

	local pm cmd sudo='sudo '
	if ((EUID == 0)); then sudo=; fi
	for pm in brew apt-get dnf zypper pacman apk nix-env; do
		if command -v "$pm" &>/dev/null; then break; fi
		pm=
	done
	case $pm in
	brew) cmd='brew install git' ;;
	apt-get | dnf | zypper) cmd="$sudo$pm install git" ;;
	# -y syncs the package lists first, and Arch needs -u with it.
	pacman) cmd="${sudo}pacman -Syu git" ;;
	apk) cmd="${sudo}apk add git" ;;
	nix-env) cmd="nix-env -f '<nixpkgs>' -iA git" ;;
	esac

	echo "envsetup needs git, but this machine has no git." >&2
	if [[ -n "$pm" ]]; then
		printf 'This machine has %s. To install git, run:\n\n  %s\n\n' "$pm" "$cmd" >&2
	else
		echo "Download git from https://git-scm.com/downloads." >&2
	fi
	echo "Then run the curl command again." >&2
	exit 1
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

envsetup::require_git

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
