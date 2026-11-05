#!/usr/bin/env bash
# This script installs Helm if it is not already on PATH.
# installers/versions.txt pins the version, for linux amd64 or arm64.
# The script checks the checksum of the download.
# It does not use get-helm-3, because that script needs sudo and openssl.
# Minimal images do not have openssl.
set -euo pipefail

source "$ENVSETUP_ROOT/lib/common.sh"

envsetup::has_cmd helm && exit 0

version=$(envsetup::pin helm)
platform="linux-$(envsetup::arch)"
sha=$(envsetup::pin helm "$platform")
envsetup::install_release "https://get.helm.sh/helm-v${version}-${platform}.tar.gz" "$sha" "$platform/helm"
