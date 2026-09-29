#!/usr/bin/env bash
# Installs the GitHub CLI (gh, linux/amd64) if it isn't already on PATH.
set -euo pipefail

source "$ENVSETUP_ROOT/lib/common.sh"

envsetup::has_cmd gh && exit 0

version="$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest |
	grep -m1 '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl -fsSL -o "$tmp/gh.tar.gz" \
	"https://github.com/cli/cli/releases/download/v${version}/gh_${version}_linux_amd64.tar.gz"
tar -xzf "$tmp/gh.tar.gz" -C "$tmp"
sudo install -m 0755 "$tmp/gh_${version}_linux_amd64/bin/gh" /usr/local/bin/gh
