#!/usr/bin/env bash
# This script installs the GitHub CLI (gh) if it is not already on PATH.
# installers/versions.txt pins the version, for linux amd64 or arm64.
# The script checks the checksum of the download.
set -euo pipefail

source "$ENVSETUP_ROOT/lib/common.sh"

envsetup::has_cmd gh && exit 0

version=$(envsetup::pin gh)
sha=$(envsetup::pin gh "linux-$(envsetup::arch)")
asset="gh_${version}_linux_$(envsetup::arch)"
envsetup::install_release "https://github.com/cli/cli/releases/download/v$version/$asset.tar.gz" "$sha" "$asset/bin/gh"
