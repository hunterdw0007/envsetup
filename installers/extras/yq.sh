#!/usr/bin/env bash
# Installs yq, mikefarah's YAML/JSON processor (latest release, linux amd64 or arm64).
set -euo pipefail

source "$ENVSETUP_ROOT/lib/common.sh"

envsetup::has_cmd yq && exit 0

# Not from the package manager: Debian and Ubuntu's "yq" is a different tool (a jq
# wrapper in Python) with other syntax.
asset="yq_linux_$(envsetup::arch)"
base=https://github.com/mikefarah/yq/releases/latest/download
# Its checksums file lists many hashes per file, in the order checksums_hashes_order gives.
readarray -t order < <(curl -fsSL "$base/checksums_hashes_order")
for i in "${!order[@]}"; do [[ "${order[i]}" == SHA-256 ]] && break; done
while read -ra fields; do
	[[ "${fields[0]}" == "$asset" ]] && sha=${fields[i + 1]}
done < <(curl -fsSL "$base/checksums")
envsetup::install_release "$base/$asset" "${sha:?no SHA-256 for $asset}" yq
