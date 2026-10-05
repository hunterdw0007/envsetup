#!/usr/bin/env bash
# Installs lazygit, the git TUI (latest release, linux x86_64 or arm64).
set -euo pipefail

source "$ENVSETUP_ROOT/lib/common.sh"

envsetup::has_cmd lazygit && exit 0

version="$(envsetup::github_latest jesseduffield/lazygit)"
arch=x86_64
[[ "$(envsetup::arch)" == arm64 ]] && arch=arm64
asset="lazygit_${version}_linux_${arch}.tar.gz"
base="https://github.com/jesseduffield/lazygit/releases/download/v$version"
envsetup::install_release "$base/$asset" "$(envsetup::release_sha256 "$base/checksums.txt" "$asset")" lazygit
