#!/usr/bin/env bash
# Shared helpers for envsetup scripts.
# shellcheck disable=SC2034 # the ENVSETUP_* constants are used by the other lib files

ENVSETUP_STATE="$HOME/.config/envsetup"
ENVSETUP_RC_BEGIN="# >>> envsetup >>>"
ENVSETUP_RC_END="# <<< envsetup <<<"

# Dry run (--dry-run, or "Preview everything"): every step that would change the
# machine checks this first and describes the change instead of making it.
envsetup::dry_run() { [[ "${ENVSETUP_DRY_RUN:-0}" == 1 ]]; }
envsetup::would() { gum style --foreground 6 "  would $*"; }
envsetup::has_cmd() { command -v "$1" &>/dev/null; }

# Runs a command as root: directly when already root (containers, WSL), else via sudo
# or doas (Alpine).
envsetup::as_root() {
	if ((EUID == 0)); then
		"$@"
	elif envsetup::has_cmd sudo; then
		sudo "$@"
	elif envsetup::has_cmd doas; then
		doas "$@"
	else
		echo "Needs root, but there's no sudo or doas: $*" >&2
		return 1
	fi
}

# os_release <KEY>: a field of /etc/os-release, e.g. ID=rocky, ID_LIKE="rhel centos fedora".
envsetup::os_release() {
	local key value
	[[ -r /etc/os-release ]] || return 0
	while IFS='=' read -r key value; do
		if [[ "$key" == "$1" ]]; then
			value=${value#[\"\']}
			echo "${value%[\"\']}"
			return 0
		fi
	done </etc/os-release
}

# amd64 or arm64, as most release downloads name them.
envsetup::arch() {
	case $HOSTTYPE in
	x86_64) echo amd64 ;;
	aarch64 | arm64) echo arm64 ;;
	*) echo "$HOSTTYPE" ;;
	esac
}

# Atomic/immutable systems (Silverblue, Bazzite, SteamOS, Aeon/MicroOS) mount /usr
# read-only, so their own package manager can't install into the running system.
envsetup::immutable() {
	local mnt opts root="" usr=""
	[[ -r /proc/mounts ]] || return 1
	while read -r _ mnt _ opts _; do
		case $mnt in
		/) root=$opts ;;
		/usr) usr=$opts ;;
		esac
	done </proc/mounts
	[[ ",${usr:-$root}," == *,ro,* ]]
}

# The version of a GitHub project's latest release, without the "v": github.com
# redirects releases/latest to the tag, which avoids the rate-limited API.
envsetup::github_latest() {
	local url
	url=$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest") || return 1
	[[ "$url" =~ /tag/v?([0-9][^/]*)$ ]] || return 1
	echo "${BASH_REMATCH[1]}"
}

envsetup::pkg_manager() {
	local cmd cmds=(brew apt-get dnf zypper pacman apk nix-env)
	if envsetup::immutable; then cmds=(brew nix-env); fi
	for cmd in "${cmds[@]}"; do
		if envsetup::has_cmd "$cmd"; then
			echo "${cmd%-*}" # apt-get -> apt, nix-env -> nix
			return 0
		fi
	done
	if envsetup::immutable; then
		echo "/usr is read-only here (Silverblue, Bazzite, SteamOS, MicroOS, ...), so the system's package manager can't install anything. Install Homebrew (https://brew.sh) and run this again." >&2
	fi
}

# pkg_name <manager> <package>: what <package> (as packages/*.txt name it) is called by
# <manager>, from packages/names.txt. Prints nothing if that manager needs nothing.
envsetup::pkg_name() {
	local -A col=([apt]=1 [dnf]=2 [zypper]=3 [pacman]=4 [apk]=5 [brew]=6 [nix]=7)
	local fields=() name=$2
	while read -ra fields; do
		if [[ "${fields[0]:-}" == "$2" ]]; then
			name=${fields[${col[$1]:-0}]:-=}
			break
		fi
	done <"$ENVSETUP_ROOT/packages/names.txt"
	case $name in
	-) ;;
	=) echo "$2" ;;
	*) echo "$name" ;;
	esac
}

# RHEL and its clones ship a smaller package set; fzf, ripgrep, bat, htop, neovim and
# about ten more of the listed packages come from EPEL. Asks before adding it.
envsetup::enable_epel() {
	local id version pkg=epel-release
	id=$(envsetup::os_release ID)
	[[ "$id" =~ ^(rhel|ol)$ || " $(envsetup::os_release ID_LIKE) " == *" rhel "* ]] || return 0
	rpm -q epel-release oracle-epel-release-el{8,9,10} &>/dev/null && return 0
	if envsetup::dry_run; then
		envsetup::would "ask to enable EPEL (Fedora's extra packages for $id), where about a third of the packages come from"
		return 0
	fi
	gum confirm "Enable EPEL? It's Fedora's add-on repo for $id; about a third of the packages come from there." || return 0
	version=$(envsetup::os_release VERSION_ID)
	version=${version%%.*}
	[[ "$id" == ol ]] && pkg=oracle-epel-release-el$version
	if ! envsetup::as_root dnf install -y "$pkg" &&
		! envsetup::as_root dnf install -y "https://dl.fedoraproject.org/pub/epel/epel-release-latest-$version.noarch.rpm"; then
		gum style --foreground 3 "Couldn't enable EPEL; installing what $id's own repos have."
		return 0
	fi
	# CodeReady Builder: some EPEL packages depend on it. epel-release ships the helper.
	if envsetup::has_cmd crb; then envsetup::as_root crb enable; fi
}

# fetch <url> <file>, with curl or wget: Ubuntu's desktop install has only wget.
envsetup::fetch() {
	if envsetup::has_cmd curl; then curl -fsSL -o "$2" "$1"; else wget -qO "$2" "$1"; fi
}

# gum_release <dir>: installs gum's latest release binary into <dir>, checksum-verified.
envsetup::gum_release() {
	local os arch asset version tmp rc=1 re
	case $OSTYPE in linux*) os=Linux ;; darwin*) os=Darwin ;; *) return 1 ;; esac
	case $HOSTTYPE in x86_64 | arm64) arch=$HOSTTYPE ;; aarch64) arch=arm64 ;; armv7*) arch=armv7 ;; *) return 1 ;; esac
	re="(gum_([^_]+)_${os}_${arch}[.]tar[.]gz)"$'\n'
	tmp=$(mktemp -d)
	# checksums.txt has no version in its name, so it also says which release is latest.
	if envsetup::fetch https://github.com/charmbracelet/gum/releases/latest/download/checksums.txt "$tmp/checksums.txt" &&
		[[ "$(<"$tmp/checksums.txt")"$'\n' =~ $re ]]; then
		asset=${BASH_REMATCH[1]} version=${BASH_REMATCH[2]}
		if envsetup::fetch "https://github.com/charmbracelet/gum/releases/download/v$version/$asset" "$tmp/$asset" &&
			(cd "$tmp" && grep " $asset\$" checksums.txt | sha256sum -c >/dev/null) &&
			tar -xzf "$tmp/$asset" -C "$tmp" && mkdir -p "$1" &&
			install -m 0755 "$tmp/${asset%.tar.gz}/gum" "$1/gum"; then
			echo "Installed gum $version to $1" >&2
			rc=0
		fi
	fi
	rm -rf "$tmp"
	return "$rc"
}

# ensure_gum: the menu needs it. The release binary in ~/.local/bin needs no sudo and
# works on any distro; Homebrew is used when it's there, Go as a last resort.
envsetup::ensure_gum() {
	local bin=$HOME/.local/bin manager
	[[ ":$PATH:" == *":$bin:"* || ! -x "$bin/gum" ]] || PATH=$bin:$PATH
	envsetup::has_cmd gum && return 0
	echo "gum not found, attempting to install it..." >&2
	if envsetup::has_cmd brew; then
		brew install gum
	else
		if ! envsetup::has_cmd curl && ! envsetup::has_cmd wget; then
			manager=$(envsetup::pkg_manager)
			if [[ -n "$manager" ]]; then envsetup::pkg_install "$manager" curl; fi
		fi
		if envsetup::gum_release "$bin"; then
			PATH=$bin:$PATH
		elif envsetup::has_cmd go; then
			go install github.com/charmbracelet/gum@latest
			PATH="$(go env GOPATH)/bin:$PATH"
		fi
	fi
	envsetup::has_cmd gum && return 0
	echo "Could not auto-install gum. See https://github.com/charmbracelet/gum#installation" >&2
	return 1
}

# pkg_install <manager> <package>...: names as packages/*.txt spell them; pkg_name maps
# them for the manager.
envsetup::pkg_install() {
	local manager=$1 pkg name prefix="" failed=() install=()
	shift
	(($#)) || return 0
	case "$manager" in
	brew) install=(brew install) ;;
	apt)
		# One broken source (e.g. a dead PPA) makes update exit non-zero even though the
		# rest refreshed; install anyway; it still fails loudly if the lists are unusable.
		envsetup::as_root apt-get update || echo "apt-get update reported errors; installing anyway." >&2
		install=(envsetup::as_root apt-get install -y)
		;;
	dnf) install=(envsetup::as_root dnf install -y) ;;
	zypper) install=(envsetup::as_root zypper --non-interactive install) ;;
	pacman)
		# A box that has never synced (a fresh container) has no package lists. Syncing
		# without upgrading is a partial upgrade, which Arch doesn't support, hence -u.
		compgen -G '/var/lib/pacman/sync/*.db' >/dev/null || envsetup::as_root pacman -Syu --noconfirm
		install=(envsetup::as_root pacman -S --noconfirm --needed)
		;;
	apk) install=(envsetup::as_root apk add) ;;
	nix)
		# Flake-style profiles (nix profile) and classic ones (nix-env) don't mix.
		if nix profile list &>/dev/null; then
			install=(nix profile install) prefix='nixpkgs#'
		else
			install=(nix-env -f '<nixpkgs>' -iA)
		fi
		;;
	*)
		echo "No supported package manager found." >&2
		return 1
		;;
	esac
	# One at a time: in a batch, one package the system can't take (a conflict, a name
	# this distro doesn't use) fails all the others with it.
	for pkg; do
		name=$(envsetup::pkg_name "$manager" "$pkg")
		if [[ -z "$name" ]]; then
			echo "Skipping $pkg: nothing to install for it with $manager." >&2
		elif ! "${install[@]}" "$prefix$name"; then
			failed+=("$pkg")
		fi
	done
	((${#failed[@]} == 0)) && return 0
	echo "Couldn't install: ${failed[*]}" >&2
	return 1
}
