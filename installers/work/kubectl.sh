#!/usr/bin/env bash
# This script installs kubectl if it is not already on PATH.
# installers/versions.txt pins the version, for linux amd64 or arm64.
# The script checks the checksum of the download.
set -euo pipefail

source "$ENVSETUP_ROOT/lib/common.sh"

envsetup::has_cmd kubectl && exit 0

version=$(envsetup::pin kubectl)
sha=$(envsetup::pin kubectl "linux-$(envsetup::arch)")
envsetup::install_release "https://dl.k8s.io/release/v${version}/bin/linux/$(envsetup::arch)/kubectl" "$sha" kubectl
