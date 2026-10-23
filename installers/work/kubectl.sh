#!/usr/bin/env bash
# Installs kubectl (pinned in installers/versions.txt; linux amd64 or arm64) if it isn't
# already on PATH, checksum-verified.
set -euo pipefail

source "$ENVSETUP_ROOT/lib/common.sh"

envsetup::has_cmd kubectl && exit 0
[[ "$OSTYPE" == darwin* ]] && exec brew install kubernetes-cli

version=$(envsetup::pin kubectl)
sha=$(envsetup::pin kubectl "linux-$(envsetup::arch)")
envsetup::install_release "https://dl.k8s.io/release/v${version}/bin/linux/$(envsetup::arch)/kubectl" "$sha" kubectl
