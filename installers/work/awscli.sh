#!/usr/bin/env bash
# This script installs or updates AWS CLI v2 (see envsetup::up_to_date).
# installers/versions.txt pins the version, for Linux x86_64 or aarch64.
# AWS publishes a signature, not a checksum.
# So the script checks the download against AWS's signing key in awscli.asc.
# The check comes before the AWS installer runs as root.
set -euo pipefail

source "$ENVSETUP_ROOT/lib/common.sh"

envsetup::up_to_date awscli aws && exit 0

# AWS's build needs glibc.
# Alpine uses musl, so it packages its own build.
if [[ "$OSTYPE" == linux-musl* ]]; then
	envsetup::pkg_install apk aws-cli
	exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

version=$(envsetup::pin awscli)
url="https://awscli.amazonaws.com/awscli-exe-linux-${HOSTTYPE}-$version.zip"
curl -fsSL -o "$tmp/awscliv2.zip" "$url"
curl -fsSL -o "$tmp/awscliv2.zip.sig" "$url.sig"
# AWS publishes the key and its fingerprint here:
# https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
envsetup::gpg_verify "$tmp/awscliv2.zip" "$tmp/awscliv2.zip.sig" "$ENVSETUP_ROOT/installers/work/awscli.asc" \
	FB5DB77FD5C118B80511ADA8A6310ACC4672475C
unzip -q "$tmp/awscliv2.zip" -d "$tmp"
# --update replaces an older AWS CLI. A first install accepts it too.
envsetup::as_root "$tmp/aws/install" --update
envsetup::record_installed awscli
