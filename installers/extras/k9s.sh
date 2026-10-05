#!/usr/bin/env bash
# Installs k9s, the Kubernetes TUI (latest release, linux amd64 or arm64).
set -euo pipefail

source "$ENVSETUP_ROOT/lib/common.sh"

envsetup::has_cmd k9s && exit 0

asset="k9s_Linux_$(envsetup::arch).tar.gz"
base=https://github.com/derailed/k9s/releases/latest/download
envsetup::install_release "$base/$asset" "$(envsetup::release_sha256 "$base/checksums.sha256" "$asset")" k9s
