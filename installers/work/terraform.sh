#!/usr/bin/env bash
# Installs Terraform (pinned in installers/versions.txt; linux amd64 or arm64) if it
# isn't already on PATH, checksum-verified.
set -euo pipefail

source "$ENVSETUP_ROOT/lib/common.sh"

envsetup::has_cmd terraform && exit 0

version=$(envsetup::pin terraform)
sha=$(envsetup::pin terraform "linux-$(envsetup::arch)")
envsetup::install_release \
	"https://releases.hashicorp.com/terraform/$version/terraform_${version}_linux_$(envsetup::arch).zip" "$sha" terraform
