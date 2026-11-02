#!/usr/bin/env bash
# Installs Helm (pinned in installers/versions.txt; linux amd64 or arm64) if it isn't
# already on PATH, checksum-verified. Not via get-helm-3: that script needs openssl,
# which minimal images lack, and sudo.
set -euo pipefail

source "$ENVSETUP_ROOT/lib/common.sh"

envsetup::has_cmd helm && exit 0

version=$(envsetup::pin helm)
platform="linux-$(envsetup::arch)"
sha=$(envsetup::pin helm "$platform")
envsetup::install_release "https://get.helm.sh/helm-v${version}-${platform}.tar.gz" "$sha" "$platform/helm"
