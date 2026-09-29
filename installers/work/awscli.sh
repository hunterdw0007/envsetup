#!/usr/bin/env bash
# Installs AWS CLI v2 (linux/x86_64) if it isn't already on PATH.
set -euo pipefail

source "$ENVSETUP_ROOT/lib/common.sh"

envsetup::has_cmd aws && exit 0

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl -fsSL -o "$tmp/awscliv2.zip" "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
unzip -q "$tmp/awscliv2.zip" -d "$tmp"
sudo "$tmp/aws/install"
