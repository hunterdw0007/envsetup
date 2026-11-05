#!/usr/bin/env bash
# This script writes installers/versions.txt again with the newest release of every pinned tool.
# It also writes the sha256 that the project publishes for each platform's download.
# Review the diff and open a PR.
# After the merge, every install checks against those versions and hashes.
# .github/workflows/bump-versions.yml runs this script every week and opens that PR (bump-pr.sh).
#
#   .github/scripts/bump-versions.sh
#
# The script prints the changes as a Markdown list.
# A failed lookup stops the script before the file changes.
# The script needs curl and git.
set -euo pipefail

ENVSETUP_ROOT=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
export ENVSETUP_ROOT
# shellcheck source=lib/common.sh
source "$ENVSETUP_ROOT/lib/common.sh"
file=$ENVSETUP_ROOT/installers/versions.txt

# These lookups live only here, never in lib/.
# Installs use the pins, not the newest version on that day.
# latest prints the version of a GitHub project's newest release, without the "v".
# github.com redirects releases/latest to the tag.
# So the script does not need the GitHub API and its rate limit.
envsetup::github_latest() {
	local url
	url=$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest") || return 1
	[[ "$url" =~ /tag/v?([0-9][^/]*)$ ]] || return 1
	echo "${BASH_REMATCH[1]}"
}

# sha <key> <checksums url> <file> prints " <key>=<sha256>", with the hash of <file> from the list.
sha() {
	local hash
	hash=$(envsetup::release_sha256 "$2" "$3")
	printf ' %s=%s' "$1" "$hash"
}

# Each name in the file has one pin_<name> function.
# The function prints "<version> <key>=<sha256>...".
# Each key is the platform that the installer asks envsetup::pin for.
pin_gum() {
	local v base arch
	v=$(envsetup::github_latest charmbracelet/gum)
	base=https://github.com/charmbracelet/gum/releases/download/v$v
	printf %s "$v"
	for arch in x86_64:amd64 arm64:arm64; do
		sha "linux-${arch#*:}" "$base/checksums.txt" "gum_${v}_Linux_${arch%:*}.tar.gz"
	done
	sha linux-armv7 "$base/checksums.txt" "gum_${v}_Linux_armv7.tar.gz"
}

pin_ohmyzsh() {
	local commit _
	read -r commit _ < <(git ls-remote https://github.com/ohmyzsh/ohmyzsh refs/heads/master)
	printf %s "${commit:?no master branch in ohmyzsh/ohmyzsh}"
}

pin_awscli() {
	local v
	# AWS tags releases on GitHub, but it publishes no GitHub releases.
	# The install checks the download against AWS's signing key.
	# So only the version is pinned.
	v=$(git ls-remote --tags --refs https://github.com/aws/aws-cli 'refs/tags/2.*' | sed 's#.*/##' | sort -V | tail -n 1)
	printf %s "${v:?no 2.x tags in aws/aws-cli}"
}

pin_gh() {
	local v arch base
	v=$(envsetup::github_latest cli/cli)
	base=https://github.com/cli/cli/releases/download/v$v
	printf %s "$v"
	for arch in amd64 arm64; do sha "linux-$arch" "$base/gh_${v}_checksums.txt" "gh_${v}_linux_$arch.tar.gz"; done
}

pin_helm() {
	local v arch url
	v=$(envsetup::github_latest helm/helm)
	printf %s "$v"
	for arch in amd64 arm64; do
		url=https://get.helm.sh/helm-v$v-linux-$arch.tar.gz
		sha "linux-$arch" "$url.sha256sum" "${url##*/}"
	done
}

pin_kubectl() {
	local v arch
	v=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
	v=${v#v}
	printf %s "$v"
	for arch in amd64 arm64; do sha "linux-$arch" "https://dl.k8s.io/release/v$v/bin/linux/$arch/kubectl.sha256" kubectl; done
}

pin_terraform() {
	local json v arch base
	json=$(curl -fsSL https://checkpoint-api.hashicorp.com/v1/check/terraform)
	[[ "$json" =~ \"current_version\":\"([^\"]+)\" ]] || return 1
	v=${BASH_REMATCH[1]}
	base=https://releases.hashicorp.com/terraform/$v
	printf %s "$v"
	for arch in amd64 arm64; do sha "linux-$arch" "$base/terraform_${v}_SHA256SUMS" "terraform_${v}_linux_$arch.zip"; done
}

pin_k9s() {
	local v arch
	v=$(envsetup::github_latest derailed/k9s)
	printf %s "$v"
	for arch in amd64 arm64; do
		sha "linux-$arch" "https://github.com/derailed/k9s/releases/download/v$v/checksums.sha256" "k9s_Linux_$arch.tar.gz"
	done
}

pin_lazygit() {
	local v base
	v=$(envsetup::github_latest jesseduffield/lazygit)
	base=https://github.com/jesseduffield/lazygit/releases/download/v$v
	printf %s "$v"
	sha linux-amd64 "$base/checksums.txt" "lazygit_${v}_linux_x86_64.tar.gz"
	sha linux-arm64 "$base/checksums.txt" "lazygit_${v}_linux_arm64.tar.gz"
}

pin_mise() {
	local v base
	v=$(envsetup::github_latest jdx/mise)
	base=https://github.com/jdx/mise/releases/download/v$v
	printf %s "$v"
	sha linux-amd64 "$base/SHASUMS256.txt" "mise-v$v-linux-x64-musl.tar.gz"
	sha linux-arm64 "$base/SHASUMS256.txt" "mise-v$v-linux-arm64-musl.tar.gz"
}

pin_starship() {
	local v arch asset
	v=$(envsetup::github_latest starship/starship)
	printf %s "$v"
	for arch in x86_64:amd64 aarch64:arm64; do
		asset=starship-${arch%:*}-unknown-linux-musl.tar.gz
		sha "linux-${arch#*:}" "https://github.com/starship/starship/releases/download/v$v/$asset.sha256" "$asset"
	done
}

pin_uv() {
	local v arch asset
	v=$(envsetup::github_latest astral-sh/uv) # uv's tags have no "v"
	printf %s "$v"
	for arch in x86_64:amd64 aarch64:arm64; do
		asset=uv-${arch%:*}-unknown-linux-musl.tar.gz
		sha "linux-${arch#*:}" "https://github.com/astral-sh/uv/releases/download/$v/$asset.sha256" "$asset"
	done
}

pin_yq() {
	local v base order i arch fields sha
	v=$(envsetup::github_latest mikefarah/yq)
	base=https://github.com/mikefarah/yq/releases/download/v$v
	printf %s "$v"
	# Its checksums file lists many hashes for each file.
	# checksums_hashes_order gives their order.
	readarray -t order < <(curl -fsSL "$base/checksums_hashes_order")
	for i in "${!order[@]}"; do [[ "${order[i]}" == SHA-256 ]] && break; done
	[[ "${order[i]:-}" == SHA-256 ]] || return 1
	for arch in amd64 arm64; do
		sha=
		while read -ra fields; do
			[[ "${fields[0]}" == "yq_linux_$arch" ]] && sha=${fields[i + 1]}
		done < <(curl -fsSL "$base/checksums")
		[[ "$sha" =~ ^[0-9a-f]{64}$ ]] || return 1
		printf ' linux-%s=%s' "$arch" "$sha"
	done
}

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
while IFS= read -r line; do
	read -r name _ <<<"$line"
	if [[ -z "$name" || "$name" == \#* ]]; then
		echo "$line"
		continue
	fi
	if ! declare -F "pin_$name" >/dev/null; then
		echo "$0 has no pin_$name function to look up $name." >&2
		exit 1
	fi
	echo "Looking up $name..." >&2
	printf '%s ' "$name"
	"pin_$name"
	echo
done <"$file" >"$tmp"
# Print the changes as Markdown on stdout.
# bump-pr.sh puts this list in the commit and the PR.
# The same version with new hashes means that the project replaced a release's files.
# Find out why before you merge.
awk 'NR == FNR { if (!/^#/ && NF) { old[$1] = $2; line[$1] = $0 }; next }
	/^#/ || !NF { next }
	old[$1] != $2 { print "- " $1 ": " (old[$1] == "" ? "new" : old[$1]) " → " $2; next }
	line[$1] != $0 { print "- " $1 ": " $2 ", **same version, other checksums**: upstream replaced its files; check why before merging" }' \
	"$file" "$tmp"
mv "$tmp" "$file"
trap - EXIT
