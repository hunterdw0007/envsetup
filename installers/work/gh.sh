#!/usr/bin/env bash
# Installs the GitHub CLI (gh, linux amd64 or arm64) if it isn't already on PATH,
# checksum-verified.
set -euo pipefail

source "$ENVSETUP_ROOT/lib/common.sh"

envsetup::has_cmd gh && exit 0
[[ "$OSTYPE" == darwin* ]] && exec brew install gh

version="$(envsetup::github_latest cli/cli)"
asset="gh_${version}_linux_$(envsetup::arch)"
base="https://github.com/cli/cli/releases/download/v${version}"
envsetup::install_release "$base/$asset.tar.gz" \
	"$(envsetup::release_sha256 "$base/gh_${version}_checksums.txt" "$asset.tar.gz")" "$asset/bin/gh"
