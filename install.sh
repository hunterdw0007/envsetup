#!/usr/bin/env bash
# install.sh starts envsetup on a new machine:
#
#   curl -fsSL https://raw.githubusercontent.com/hunterdw0007/envsetup/main/install.sh | bash
#
# It clones the newest release to a temporary folder.
# It downloads that release's envsetup binary and checks its sha256.
# It runs the setup.sh menu from that folder.
# When the menu ends, in any way, it deletes the folder.
# Before that, "Link shell config" copies what new shells need out of the folder.
# Arguments go to setup.sh.
# For example, `... | bash -s -- --dry-run` opens the menu without changing anything.
# ENVSETUP_VERSION selects another release (v1.2.0 or 1.2.0), or a branch or commit.
# A branch or a commit has no binary to download.
# So setup.sh builds envsetup with Go, or says how to get a release.
# Releases before Go (v1.0.0 and older) run their own setup.sh, as before.
# ENVSETUP_DOWNLOAD_URL names where the binaries are, for a clone that is not on GitHub.
# ENVSETUP_BIN names a binary to run instead, and install.sh then downloads none.
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

	local pm cmd as='' how='To install git, run:'
	for pm in brew apt-get dnf zypper pacman apk nix-env; do
		if command -v "$pm" &>/dev/null; then break; fi
		pm=
	done
	# The system's package managers need root.
	# brew and nix-env do not.
	if [[ -n "$pm" && "$pm" != brew && "$pm" != nix-env ]] && ((EUID != 0)); then
		if command -v sudo &>/dev/null; then
			as='sudo '
		elif command -v doas &>/dev/null; then
			as='doas '
		else
			how='As root, run:'
		fi
	fi
	case $pm in
	brew) cmd='brew install git' ;;
	# A new machine may have no package lists yet.
	apt-get) cmd="${as}apt-get update && ${as}apt-get install git" ;;
	dnf | zypper) cmd="$as$pm install git" ;;
	# -y syncs the package lists first.
	# Arch needs -u together with -y.
	pacman) cmd="${as}pacman -Syu git" ;;
	apk) cmd="${as}apk add git" ;;
	nix-env) cmd="nix-env -f '<nixpkgs>' -iA git" ;;
	esac

	echo "envsetup needs git, but this machine has no git." >&2
	if [[ -n "$pm" ]]; then
		printf 'This machine has %s. %s\n\n  %s\n\n' "$pm" "$how" "$cmd" >&2
	else
		echo "Download git from https://git-scm.com/downloads." >&2
	fi
	echo "Then run the curl command again." >&2
	exit 1
}

# git_local runs git in the download without the user's global config.
# An older envsetup wrote zdiff3 there, and git 2.34 then fails on checkout.
# clone keeps the global config, because it can hold a proxy or a URL rewrite.
envsetup::git_local() {
	GIT_CONFIG_GLOBAL=/dev/null git -C "$download" "$@"
}

# releases prints the release tags (vX.Y.Z), newest first.
# It leaves out test releases such as v1.2.0-rc.1.
envsetup::releases() {
	local tag
	while read -r tag; do
		if [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo "$tag"; fi
	done < <(envsetup::git_local tag --list 'v*' --sort=-v:refname)
}

# use_version <version> checks out a version, detached from any branch.
# The version can be a release (v1.2.0 or 1.2.0), a branch or a commit.
# "latest" means the newest release.
# Before the first release, "latest" means the default branch.
envsetup::use_version() {
	local ref=$1 releases target
	if [[ "$ref" == latest ]]; then
		read -r ref < <(envsetup::releases) || true
		if [[ -z "$ref" ]]; then
			ref=$(envsetup::git_local symbolic-ref -q --short refs/remotes/origin/HEAD || true)
			ref=${ref#origin/}
		fi
		if [[ -z "$ref" ]]; then
			echo "envsetup has no releases and no default branch yet. Using the checked-out commit."
			return 0
		fi
	fi
	if [[ "$ref" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then ref=v$ref; fi

	if envsetup::git_local show-ref -q --verify "refs/tags/$ref"; then
		target=refs/tags/$ref
	elif envsetup::git_local show-ref -q --verify "refs/remotes/origin/$ref"; then
		target=origin/$ref
	elif envsetup::git_local rev-parse -q --verify "$ref^{commit}" >/dev/null; then
		target=$ref
	else
		echo "envsetup has no release, branch or commit called \"$1\"." >&2
		releases=$(envsetup::releases)
		if [[ -n "$releases" ]]; then
			printf 'Releases, newest first:\n  %s\n' "${releases//$'\n'/$'\n'  }" >&2
		fi
		exit 1
	fi
	envsetup::git_local checkout -q --detach "$target"
}

# fetch <url> <file> downloads a file with curl, or with wget when there is no curl.
# Ubuntu's desktop install has only wget.
envsetup::fetch() {
	local rc=0
	if command -v curl &>/dev/null; then
		curl -fsSL -o "$2" "$1" || rc=$?
	elif command -v wget &>/dev/null; then
		wget -qO "$2" "$1" || rc=$?
	else
		echo "envsetup needs curl or wget to download its release. Install one, then run the curl command again." >&2
		exit 1
	fi
	if ((rc != 0)); then
		echo "envsetup could not download $1. Check the network, then run the curl command again." >&2
		exit 1
	fi
}

# download_release <tag> downloads the release's envsetup binary for this machine to bin/envsetup.
# It checks the sha256 against the release's SHA256SUMS before anything runs the binary.
envsetup::download_release() {
	local tag=$1 arch base name sum file want='' got
	case $(uname -m) in
	x86_64 | amd64) arch=amd64 ;;
	aarch64 | arm64) arch=arm64 ;;
	*)
		echo "envsetup has release binaries for amd64 and arm64 only. This machine is $(uname -m)." >&2
		exit 1
		;;
	esac
	base=${ENVSETUP_DOWNLOAD_URL:-}
	if [[ -z "$base" ]]; then
		if [[ "$REPO_URL" =~ ^(https://github\.com/|git@github\.com:|ssh://git@github\.com/)([^/]+)/([^/]+)$ ]]; then
			base=https://github.com/${BASH_REMATCH[2]}/${BASH_REMATCH[3]%.git}/releases/download
		else
			echo "envsetup cannot tell where $REPO_URL keeps its release binaries." >&2
			echo "Set ENVSETUP_DOWNLOAD_URL to the URL that holds <tag>/envsetup-linux-$arch, then run the curl command again." >&2
			exit 1
		fi
	fi
	name=envsetup-linux-$arch
	mkdir -p "$download/bin"
	envsetup::fetch "$base/$tag/$name" "$download/bin/envsetup"
	envsetup::fetch "$base/$tag/SHA256SUMS" "$download/bin/SHA256SUMS"
	# sha256sum marks a binary file with a * before its name.
	while read -r sum file; do
		if [[ "${file#\*}" == "$name" ]]; then want=$sum; fi
	done <"$download/bin/SHA256SUMS"
	got=$(sha256sum "$download/bin/envsetup")
	got=${got%% *}
	if [[ -z "$want" || "$got" != "$want" ]]; then
		echo "The download of $name for $tag does not match its sha256 in SHA256SUMS, so envsetup does not run it." >&2
		echo "Run the curl command again. If it fails again, report it at https://github.com/hunterdw0007/envsetup/issues." >&2
		exit 1
	fi
	chmod +x "$download/bin/envsetup"
	export ENVSETUP_BIN=$download/bin/envsetup
}

envsetup::require_git

download=$(mktemp -d)
trap 'rm -rf "$download"' EXIT
# A signal (Ctrl-C, a closed terminal, kill) would otherwise skip the EXIT trap.
trap 'exit 130' INT TERM HUP
git clone -q "$REPO_URL" "$download"
envsetup::use_version "$ENVSETUP_VERSION"
echo "Downloaded envsetup $(envsetup::git_local describe --tags --always) to $download. envsetup deletes this folder when setup ends."

# Only a release has a binary to download.
# A release before Go has no cmd/envsetup, and its setup.sh needs no binary.
if [[ -z "${ENVSETUP_BIN:-}" && -d "$download/cmd/envsetup" ]]; then
	while read -r tag; do
		if [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
			envsetup::download_release "$tag"
			break
		fi
	done < <(envsetup::git_local tag --points-at HEAD)
fi

# setup.sh reads from the terminal.
# Under `curl ... | bash`, stdin is the pipe from curl.
# The questions in setup.sh would then get no input.
# This line does not use exec, so the traps above still run.
"$download/setup.sh" "$@" </dev/tty
