#!/usr/bin/env bash
# Rewrites installers/versions.txt with the newest release of every tool it pins, and the
# sha256 of each platform's download as the project publishes it. Review the diff and
# open a PR: once merged, those are the versions and hashes every install checks against.
# .github/workflows/bump-versions.yml runs it weekly and opens that PR (bump-pr.sh).
#
#   .github/scripts/bump-versions.sh
#
# Prints what changed as a Markdown list. Any lookup that fails stops it before the file
# changes. Needs curl and git.
set -euo pipefail

ENVSETUP_ROOT=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
export ENVSETUP_ROOT
# shellcheck source=lib/common.sh
source "$ENVSETUP_ROOT/lib/common.sh"
file=$ENVSETUP_ROOT/installers/versions.txt

# Only here, never in lib/: installs use the pins, not what is newest that day.
# The version of a GitHub project's latest release, without the "v": github.com
# redirects releases/latest to the tag, which avoids the rate-limited API.
envsetup::github_latest() {
	local url
	url=$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest") || return 1
	[[ "$url" =~ /tag/v?([0-9][^/]*)$ ]] || return 1
	echo "${BASH_REMATCH[1]}"
}

# sha <key> <checksums url> <file>: " <key>=<sha256>", <file>'s hash from the list.
sha() {
	local hash
	hash=$(envsetup::release_sha256 "$2" "$3")
	printf ' %s=%s' "$1" "$hash"
}

# One pin_<name> per name in the file: prints "<version> <key>=<sha256>...", where each key is
# the platform the installer asks envsetup::pin for.
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
	# AWS tags releases on GitHub but publishes no GitHub releases; the download is
	# checked against its signing key at install time, so only the version is pinned.
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
	# Its checksums file lists many hashes per file, in the order checksums_hashes_order gives.
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
		echo "No pin_$name in $0 to look up $name with." >&2
		exit 1
	fi
	echo "Looking up $name..." >&2
	printf '%s ' "$name"
	"pin_$name"
	echo
done <"$file" >"$tmp"
# What changed, as Markdown on stdout (bump-pr.sh puts it in the commit and the PR). The
# same version with other hashes means upstream replaced a release's files: find out why.
awk 'NR == FNR { if (!/^#/ && NF) { old[$1] = $2; line[$1] = $0 }; next }
	/^#/ || !NF { next }
	old[$1] != $2 { print "- " $1 ": " (old[$1] == "" ? "new" : old[$1]) " → " $2; next }
	line[$1] != $0 { print "- " $1 ": " $2 ", **same version, other checksums**: upstream replaced its files; check why before merging" }' \
	"$file" "$tmp"
mv "$tmp" "$file"
trap - EXIT
