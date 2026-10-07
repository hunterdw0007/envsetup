#!/usr/bin/env bash
# Installs Helm (latest release, linux amd64 or arm64) if it isn't already on PATH.
# Not via get-helm-3: that script needs openssl, which minimal images lack, and sudo.
set -euo pipefail

source "$ENVSETUP_ROOT/lib/common.sh"

envsetup::has_cmd helm && exit 0
[[ "$OSTYPE" == darwin* ]] && exec brew install helm

version="$(envsetup::github_latest helm/helm)"
platform="linux-$(envsetup::arch)"
asset="helm-v${version}-${platform}.tar.gz"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl -fsSL -o "$tmp/$asset" "https://get.helm.sh/$asset"
curl -fsSL -o "$tmp/$asset.sha256sum" "https://get.helm.sh/$asset.sha256sum"
(cd "$tmp" && sha256sum -c "$asset.sha256sum" >/dev/null)
tar -xzf "$tmp/$asset" -C "$tmp"
envsetup::as_root install -m 0755 "$tmp/$platform/helm" /usr/local/bin/helm
