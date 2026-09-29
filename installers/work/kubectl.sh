#!/usr/bin/env bash
# Installs kubectl (stable channel) if it isn't already on PATH.
set -euo pipefail

source "$ENVSETUP_ROOT/lib/common.sh"

envsetup::has_cmd kubectl && exit 0

version="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl -fsSL -o "$tmp/kubectl" "https://dl.k8s.io/release/${version}/bin/linux/amd64/kubectl"
chmod +x "$tmp/kubectl"
sudo install -o root -g root -m 0755 "$tmp/kubectl" /usr/local/bin/kubectl
