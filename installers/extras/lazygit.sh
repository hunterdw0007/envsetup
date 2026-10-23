#!/usr/bin/env bash
# Installs lazygit, the git TUI (pinned in installers/versions.txt; linux x86_64 or arm64).
set -euo pipefail

source "$ENVSETUP_ROOT/lib/common.sh"

envsetup::has_cmd lazygit && exit 0
[[ "$OSTYPE" == darwin* ]] && exec brew install lazygit

version=$(envsetup::pin lazygit)
sha=$(envsetup::pin lazygit "linux-$(envsetup::arch)")
arch=x86_64
[[ "$(envsetup::arch)" == arm64 ]] && arch=arm64
asset="lazygit_${version}_linux_${arch}.tar.gz"
envsetup::install_release "https://github.com/jesseduffield/lazygit/releases/download/v$version/$asset" "$sha" lazygit
