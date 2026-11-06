#!/usr/bin/env bash
# This script installs starship, a prompt for any shell.
# installers/versions.txt pins the version, for linux x86_64 or aarch64.
# The build is static.
set -euo pipefail

source "$ENVSETUP_ROOT/lib/common.sh"

envsetup::up_to_date starship starship && exit 0

# The install does not change your prompt.
# To use starship, add `eval "$(starship init bash)"` (or zsh) to config.sh.
# config.sh loads after envsetup's own prompt.
version=$(envsetup::pin starship)
sha=$(envsetup::pin starship "linux-$(envsetup::arch)")
envsetup::install_release \
	"https://github.com/starship/starship/releases/download/v$version/starship-${HOSTTYPE}-unknown-linux-musl.tar.gz" "$sha" starship
envsetup::record_installed starship
