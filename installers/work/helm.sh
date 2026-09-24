#!/usr/bin/env bash
# Installs Helm via the official get-helm-3 script if it isn't already on PATH.
set -euo pipefail

source "$ENVSETUP_ROOT/lib/common.sh"

envsetup::has_cmd helm && exit 0

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl -fsSL -o "$tmp/get-helm-3" https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod +x "$tmp/get-helm-3"
"$tmp/get-helm-3"
