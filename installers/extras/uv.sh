#!/usr/bin/env bash
# Installs uv and uvx, Astral's Python package and project manager (latest release, linux x86_64 or aarch64, static).
set -euo pipefail

source "$ENVSETUP_ROOT/lib/common.sh"

envsetup::has_cmd uv && exit 0

dir="uv-${HOSTTYPE}-unknown-linux-musl"
base=https://github.com/astral-sh/uv/releases/latest/download
envsetup::install_release "$base/$dir.tar.gz" "$(envsetup::release_sha256 "$base/$dir.tar.gz.sha256" "$dir.tar.gz")" "$dir/uv" "$dir/uvx"
