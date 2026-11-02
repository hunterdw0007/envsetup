#!/usr/bin/env bash
# Installs the GitHub CLI (gh, pinned in installers/versions.txt; linux amd64 or arm64)
# if it isn't already on PATH, checksum-verified.
set -euo pipefail

source "$ENVSETUP_ROOT/lib/common.sh"

envsetup::has_cmd gh && exit 0

version=$(envsetup::pin gh)
sha=$(envsetup::pin gh "linux-$(envsetup::arch)")
asset="gh_${version}_linux_$(envsetup::arch)"
envsetup::install_release "https://github.com/cli/cli/releases/download/v$version/$asset.tar.gz" "$sha" "$asset/bin/gh"
