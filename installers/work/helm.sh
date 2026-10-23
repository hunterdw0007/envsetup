#!/usr/bin/env bash
# Installs Helm (latest release, linux amd64 or arm64) if it isn't already on PATH,
# checksum-verified. Not via get-helm-3: that script needs openssl, which minimal images
# lack, and sudo.
set -euo pipefail

source "$ENVSETUP_ROOT/lib/common.sh"

envsetup::has_cmd helm && exit 0
[[ "$OSTYPE" == darwin* ]] && exec brew install helm

version="$(envsetup::github_latest helm/helm)"
platform="linux-$(envsetup::arch)"
url="https://get.helm.sh/helm-v${version}-${platform}.tar.gz"
envsetup::install_release "$url" "$(envsetup::release_sha256 "$url.sha256sum" "${url##*/}")" "$platform/helm"
