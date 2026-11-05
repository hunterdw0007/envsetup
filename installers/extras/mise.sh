#!/usr/bin/env bash
# This script installs mise, which sets the tool and runtime versions for each project.
# installers/versions.txt pins the version, for linux x64 or arm64.
# The build is static.
set -euo pipefail

source "$ENVSETUP_ROOT/lib/common.sh"

envsetup::has_cmd mise && exit 0

# shell/shared/tools.sh turns it on in new shells.
version=$(envsetup::pin mise)
sha=$(envsetup::pin mise "linux-$(envsetup::arch)")
arch=x64
[[ "$(envsetup::arch)" == arm64 ]] && arch=arm64
asset="mise-v${version}-linux-${arch}-musl.tar.gz"
envsetup::install_release "https://github.com/jdx/mise/releases/download/v$version/$asset" "$sha" mise/bin/mise
