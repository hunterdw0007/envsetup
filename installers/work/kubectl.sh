#!/usr/bin/env bash
# Installs kubectl (stable channel, linux amd64 or arm64) if it isn't already on PATH.
set -euo pipefail

source "$ENVSETUP_ROOT/lib/common.sh"

envsetup::has_cmd kubectl && exit 0
envsetup::macos_brew kubernetes-cli

version="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl -fsSL -o "$tmp/kubectl" "https://dl.k8s.io/release/${version}/bin/linux/$(envsetup::arch)/kubectl"
chmod +x "$tmp/kubectl"
envsetup::as_root install -o root -g root -m 0755 "$tmp/kubectl" /usr/local/bin/kubectl
