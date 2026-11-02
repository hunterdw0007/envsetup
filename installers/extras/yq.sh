#!/usr/bin/env bash
# Installs yq, mikefarah's YAML/JSON processor (pinned in installers/versions.txt; linux amd64 or arm64).
set -euo pipefail

source "$ENVSETUP_ROOT/lib/common.sh"

envsetup::has_cmd yq && exit 0

# Not from the package manager: Debian and Ubuntu's "yq" is a different tool (a jq
# wrapper in Python) with other syntax.
version=$(envsetup::pin yq)
sha=$(envsetup::pin yq "linux-$(envsetup::arch)")
envsetup::install_release "https://github.com/mikefarah/yq/releases/download/v$version/yq_linux_$(envsetup::arch)" "$sha" yq
