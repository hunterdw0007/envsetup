#!/usr/bin/env bash
# Installs kubectl (stable channel, linux amd64 or arm64) if it isn't already on PATH,
# checksum-verified.
set -euo pipefail

source "$ENVSETUP_ROOT/lib/common.sh"

envsetup::has_cmd kubectl && exit 0
[[ "$OSTYPE" == darwin* ]] && exec brew install kubernetes-cli

version="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
url="https://dl.k8s.io/release/${version}/bin/linux/$(envsetup::arch)/kubectl"
envsetup::install_release "$url" "$(envsetup::release_sha256 "$url.sha256" kubectl)" kubectl
