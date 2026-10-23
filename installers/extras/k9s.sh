#!/usr/bin/env bash
# Installs k9s, the Kubernetes TUI (pinned in installers/versions.txt; linux amd64 or arm64).
set -euo pipefail

source "$ENVSETUP_ROOT/lib/common.sh"

envsetup::has_cmd k9s && exit 0
[[ "$OSTYPE" == darwin* ]] && exec brew install k9s

version=$(envsetup::pin k9s)
sha=$(envsetup::pin k9s "linux-$(envsetup::arch)")
envsetup::install_release "https://github.com/derailed/k9s/releases/download/v$version/k9s_Linux_$(envsetup::arch).tar.gz" "$sha" k9s
