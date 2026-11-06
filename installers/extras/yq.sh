#!/usr/bin/env bash
# This script installs yq, mikefarah's YAML and JSON processor.
# installers/versions.txt pins the version, for linux amd64 or arm64.
set -euo pipefail

source "$ENVSETUP_ROOT/lib/common.sh"

envsetup::up_to_date yq yq && exit 0

# This script does not use the package manager.
# The "yq" package of Debian and Ubuntu is a different tool with a different syntax.
# That tool is a Python program around jq.
version=$(envsetup::pin yq)
sha=$(envsetup::pin yq "linux-$(envsetup::arch)")
envsetup::install_release "https://github.com/mikefarah/yq/releases/download/v$version/yq_linux_$(envsetup::arch)" "$sha" yq
envsetup::record_installed yq
