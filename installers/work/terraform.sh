#!/usr/bin/env bash
# Installs Terraform (current release, linux/amd64) if it isn't already on PATH.
set -euo pipefail

source "$ENVSETUP_ROOT/lib/common.sh"

envsetup::has_cmd terraform && exit 0

version="$(curl -fsSL https://checkpoint-api.hashicorp.com/v1/check/terraform |
	grep -o '"current_version":"[^"]*"' | cut -d'"' -f4)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl -fsSL -o "$tmp/terraform.zip" \
	"https://releases.hashicorp.com/terraform/${version}/terraform_${version}_linux_amd64.zip"
unzip -q "$tmp/terraform.zip" -d "$tmp"
sudo install -m 0755 "$tmp/terraform" /usr/local/bin/terraform
