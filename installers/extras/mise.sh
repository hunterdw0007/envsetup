#!/usr/bin/env bash
# Installs mise, the polyglot tool/runtime version manager (latest release, linux x64 or arm64, static).
set -euo pipefail

source "$ENVSETUP_ROOT/lib/common.sh"

envsetup::has_cmd mise && exit 0
[[ "$OSTYPE" == darwin* ]] && exec brew install mise

# shell/shared/tools.sh activates it in new shells.
version="$(envsetup::github_latest jdx/mise)"
arch=x64
[[ "$(envsetup::arch)" == arm64 ]] && arch=arm64
asset="mise-v${version}-linux-${arch}-musl.tar.gz"
base="https://github.com/jdx/mise/releases/download/v$version"
envsetup::install_release "$base/$asset" "$(envsetup::release_sha256 "$base/SHASUMS256.txt" "$asset")" mise/bin/mise
