#!/usr/bin/env bash
# This script installs uv and uvx, Astral's Python package and project manager.
# installers/versions.txt pins the version, for linux x86_64 or aarch64.
# The build is static.
set -euo pipefail

source "$ENVSETUP_ROOT/lib/common.sh"

envsetup::has_cmd uv && exit 0

version=$(envsetup::pin uv)
sha=$(envsetup::pin uv "linux-$(envsetup::arch)")
dir="uv-${HOSTTYPE}-unknown-linux-musl"
# uv's release tags do not start with "v".
envsetup::install_release "https://github.com/astral-sh/uv/releases/download/$version/$dir.tar.gz" "$sha" "$dir/uv" "$dir/uvx"
