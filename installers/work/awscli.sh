#!/usr/bin/env bash
# Installs AWS CLI v2 (Linux x86_64 or aarch64) if it isn't already on PATH.
set -euo pipefail

source "$ENVSETUP_ROOT/lib/common.sh"

envsetup::has_cmd aws && exit 0

# AWS's build needs glibc; Alpine (musl) packages its own.
if [[ "$OSTYPE" == linux-musl* ]]; then
	envsetup::as_root apk add aws-cli
	exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl -fsSL -o "$tmp/awscliv2.zip" "https://awscli.amazonaws.com/awscli-exe-linux-${HOSTTYPE}.zip"
unzip -q "$tmp/awscliv2.zip" -d "$tmp"
envsetup::as_root "$tmp/aws/install"
