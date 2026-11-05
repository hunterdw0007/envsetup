#!/usr/bin/env bash
# This script installs Terraform if it is not already on PATH.
# installers/versions.txt pins the version, for linux amd64 or arm64.
# The script checks the checksum of the download.
set -euo pipefail

source "$ENVSETUP_ROOT/lib/common.sh"

envsetup::has_cmd terraform && exit 0

version=$(envsetup::pin terraform)
sha=$(envsetup::pin terraform "linux-$(envsetup::arch)")
envsetup::install_release \
	"https://releases.hashicorp.com/terraform/$version/terraform_${version}_linux_$(envsetup::arch).zip" "$sha" terraform
