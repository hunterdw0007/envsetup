#!/usr/bin/env bash
# This script installs or updates Terraform (see envsetup::up_to_date).
# installers/versions.txt pins the version, for linux amd64 or arm64.
# The script checks the checksum of the download.
set -euo pipefail

source "$ENVSETUP_ROOT/lib/common.sh"

envsetup::up_to_date terraform terraform && exit 0

version=$(envsetup::pin terraform)
sha=$(envsetup::pin terraform "linux-$(envsetup::arch)")
envsetup::install_release \
	"https://releases.hashicorp.com/terraform/$version/terraform_${version}_linux_$(envsetup::arch).zip" "$sha" terraform
envsetup::record_installed terraform
