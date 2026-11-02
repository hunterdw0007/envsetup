#!/usr/bin/env bash
# Installs AWS CLI v2 (pinned in installers/versions.txt; Linux x86_64 or aarch64) if it
# isn't already on PATH. AWS publishes a signature, not a checksum, so the download is
# checked against AWS's signing key in awscli.asc before its installer runs as root.
set -euo pipefail

source "$ENVSETUP_ROOT/lib/common.sh"

envsetup::has_cmd aws && exit 0

# AWS's build needs glibc; Alpine (musl) packages its own.
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
# The key and its fingerprint as AWS publishes them:
# https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
envsetup::gpg_verify "$tmp/awscliv2.zip" "$tmp/awscliv2.zip.sig" "$ENVSETUP_ROOT/installers/work/awscli.asc" \
	FB5DB77FD5C118B80511ADA8A6310ACC4672475C
unzip -q "$tmp/awscliv2.zip" -d "$tmp"
envsetup::as_root "$tmp/aws/install"
