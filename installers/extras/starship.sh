#!/usr/bin/env bash
# Installs starship, the cross-shell prompt (latest release, linux x86_64 or aarch64, static).
set -euo pipefail

source "$ENVSETUP_ROOT/lib/common.sh"

envsetup::has_cmd starship && exit 0
envsetup::macos_brew starship

# Installing doesn't switch your prompt: add `eval "$(starship init bash)"` (or zsh) to
# config.sh, which loads after envsetup's own prompt.
asset="starship-${HOSTTYPE}-unknown-linux-musl.tar.gz"
base=https://github.com/starship/starship/releases/latest/download
envsetup::install_release "$base/$asset" "$(envsetup::release_sha256 "$base/$asset.sha256" "$asset")" starship
