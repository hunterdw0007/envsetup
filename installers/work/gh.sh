#!/usr/bin/env bash
# Installs the GitHub CLI (gh, linux amd64 or arm64) if it isn't already on PATH.
set -euo pipefail

source "$ENVSETUP_ROOT/lib/common.sh"

envsetup::has_cmd gh && exit 0
[[ "$OSTYPE" == darwin* ]] && exec brew install gh

version="$(envsetup::github_latest cli/cli)"
asset="gh_${version}_linux_$(envsetup::arch)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl -fsSL -o "$tmp/gh.tar.gz" "https://github.com/cli/cli/releases/download/v${version}/${asset}.tar.gz"
tar -xzf "$tmp/gh.tar.gz" -C "$tmp"
envsetup::as_root install -m 0755 "$tmp/${asset}/bin/gh" /usr/local/bin/gh
