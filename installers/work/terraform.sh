#!/usr/bin/env bash
# Installs Terraform (current release, linux amd64 or arm64) if it isn't already on PATH,
# checksum-verified.
set -euo pipefail

source "$ENVSETUP_ROOT/lib/common.sh"

envsetup::has_cmd terraform && exit 0
# Homebrew's own tap dropped terraform after its license change; HashiCorp keeps one.
[[ "$OSTYPE" == darwin* ]] && exec brew install hashicorp/tap/terraform

json=$(curl -fsSL https://checkpoint-api.hashicorp.com/v1/check/terraform)
if ! [[ "$json" =~ \"current_version\":\"([^\"]+)\" ]]; then
	echo "Couldn't read Terraform's current version from HashiCorp's checkpoint API." >&2
	exit 1
fi
version=${BASH_REMATCH[1]}
asset="terraform_${version}_linux_$(envsetup::arch).zip"
base="https://releases.hashicorp.com/terraform/${version}"
envsetup::install_release "$base/$asset" \
	"$(envsetup::release_sha256 "$base/terraform_${version}_SHA256SUMS" "$asset")" terraform
