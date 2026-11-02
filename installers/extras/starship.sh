#!/usr/bin/env bash
# Installs starship, the cross-shell prompt (pinned in installers/versions.txt; linux x86_64 or aarch64, static).
set -euo pipefail

source "$ENVSETUP_ROOT/lib/common.sh"

envsetup::has_cmd starship && exit 0

# Installing doesn't switch your prompt: add `eval "$(starship init bash)"` (or zsh) to
# config.sh, which loads after envsetup's own prompt.
version=$(envsetup::pin starship)
sha=$(envsetup::pin starship "linux-$(envsetup::arch)")
envsetup::install_release \
	"https://github.com/starship/starship/releases/download/v$version/starship-${HOSTTYPE}-unknown-linux-musl.tar.gz" "$sha" starship
