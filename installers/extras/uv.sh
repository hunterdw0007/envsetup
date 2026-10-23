#!/usr/bin/env bash
# Installs uv and uvx, Astral's Python package and project manager (pinned in installers/versions.txt; linux x86_64 or aarch64, static).
set -euo pipefail

source "$ENVSETUP_ROOT/lib/common.sh"

envsetup::has_cmd uv && exit 0
[[ "$OSTYPE" == darwin* ]] && exec brew install uv

version=$(envsetup::pin uv)
sha=$(envsetup::pin uv "linux-$(envsetup::arch)")
dir="uv-${HOSTTYPE}-unknown-linux-musl"
# uv's release tags have no "v".
envsetup::install_release "https://github.com/astral-sh/uv/releases/download/$version/$dir.tar.gz" "$sha" "$dir/uv" "$dir/uvx"
