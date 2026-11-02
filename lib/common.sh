#!/usr/bin/env bash
# Shared helpers for envsetup scripts.
# shellcheck disable=SC2034 # the ENVSETUP_* constants are used by the other lib files

# shellcheck source=shell/state.sh
source "$ENVSETUP_ROOT/shell/state.sh"
ENVSETUP_RC_BEGIN="# >>> envsetup >>>"
ENVSETUP_RC_END="# <<< envsetup <<<"
ENVSETUP_CHSH_MARKER="$ENVSETUP_STATE/chsh" # exists once envsetup switched you to zsh
# The copy of shell/ that new shells load (see envsetup::copy_shell), and its release.
ENVSETUP_DATA=$HOME/.local/share/envsetup
if [[ "${XDG_DATA_HOME:-}" == /* ]]; then ENVSETUP_DATA=$XDG_DATA_HOME/envsetup; fi

# Dry run (--dry-run, or "Preview everything"): every step that would change the
# machine checks this first and describes the change instead of making it.
envsetup::dry_run() { [[ "${ENVSETUP_DRY_RUN:-0}" == 1 ]]; }
envsetup::would() { gum style --foreground 6 "  would $*"; }
envsetup::has_cmd() { command -v "$1" &>/dev/null; }

# The checked-out release (v1.2.0), "v1.2.0-3-gabc1234" three commits past it, a bare
# commit before the first release; "-dirty" when tracked files were edited. Outside a
# checkout, the release envsetup::copy_shell recorded.
envsetup::version() {
	git -C "$ENVSETUP_ROOT" describe --tags --match 'v[0-9]*' --always --dirty 2>/dev/null ||
		cat "$ENVSETUP_DATA/version" 2>/dev/null || echo unknown
}

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

# pin <name> [<platform>]: <name>'s version from installers/versions.txt, or with
# <platform> (a key there, e.g. linux-amd64) the sha256 of that platform's download.
envsetup::pin() {
	local name version sums
	while read -r name version sums; do
		[[ "$name" == "$1" && -n "$version" ]] || continue
		if [[ -z "${2:-}" ]]; then
			echo "$version"
			return 0
		elif [[ " $sums " =~ \ "$2"=([0-9a-f]{64})\  ]]; then
			echo "${BASH_REMATCH[1]}"
			return 0
		fi
		echo "installers/versions.txt has no checksum of $1 for $2." >&2
		return 1
	done <"$ENVSETUP_ROOT/installers/versions.txt"
	echo "installers/versions.txt has no version of $1." >&2
	return 1
}

# release_sha256 <checksums url> <file>: <file>'s hash from a project's sha256 list,
# either "<hash>  <file>" lines (sha256sum's format, "*file" and "./file" too) or the
# bare hash of a one-file .sha256.
envsetup::release_sha256() {
	local hash file sums
	sums=$(curl -fsSL "$1") || return 1
	while read -r hash file; do
		file=${file#\*}
		file=${file#./}
		if [[ "$file" == "$2" || (-z "$file" && "$hash" =~ ^[0-9a-f]{64}$) ]]; then
			echo "$hash"
			return 0
		fi
	done <<<"$sums"
	echo "No checksum for $2 in $1" >&2
	return 1
}

# install_release <url> <sha256> <member>...: downloads a release (a .tar.gz, a .zip, or
# a bare binary), checks its hash, and installs each member (a path inside the archive,
# or the binary's name) into /usr/local/bin under its base name.
envsetup::install_release() (
	url=$1 sha=$2 tmp=$(mktemp -d)
	shift 2
	trap 'rm -rf "$tmp"' EXIT
	file=$tmp/download-${url##*/}
	curl -fsSL -o "$file" "$url"
	if ! echo "$sha  $file" | sha256sum -c >/dev/null 2>&1; then
		echo "${url##*/} doesn't match its published checksum; not installing it." >&2
		exit 1
	fi
	case $file in
	*.tar.gz) tar -xzf "$file" -C "$tmp" ;;
	*.zip) unzip -q "$file" -d "$tmp" ;;
	*) mv "$file" "$tmp/$1" ;;
	esac
	for member; do
		envsetup::as_root install -m 0755 "$tmp/$member" "/usr/local/bin/${member##*/}"
	done
)

# gpg_verify <file> <signature> <key.asc> <fingerprint>: checks a detached signature
# against a key kept in this repo, and passes only if it's a valid signature by exactly
# that key. "Expired" alone doesn't fail it: vendors extend a key's expiry date and keep
# signing with it, so the copy here goes stale while the key stays the same. gpgv (which
# Debian and Ubuntu always have; gpg often isn't installed) reads only binary keyrings,
# hence the dearmoring.
envsetup::gpg_verify() (
	file=$1 sig=$2 key=$3 fpr=$4 tmp=$(mktemp -d) body=false status=
	trap 'rm -rf "$tmp"' EXIT
	while IFS= read -r line; do
		[[ $line == -----END* ]] && break
		if $body; then
			[[ $line == =* ]] || printf '%s\n' "$line" # skip the armor's checksum line
		elif [[ -z ${line//[[:space:]]/} ]]; then
			body=true
		fi
	done <"$key" | base64 -d >"$tmp/key.gpg"
	if envsetup::has_cmd gpgv; then
		status=$(gpgv --keyring "$tmp/key.gpg" --status-fd 1 "$sig" "$file" 2>/dev/null) || true
	elif envsetup::has_cmd gpg; then
		status=$(gpg --homedir "$tmp" --no-default-keyring --keyring "$tmp/key.gpg" --batch \
			--status-fd 1 --verify "$sig" "$file" 2>/dev/null) || true
	else
		echo "Can't check ${file##*/}'s signature without gpgv or gpg (install gnupg)." >&2
		exit 1
	fi
	if [[ $'\n'"$status" != *$'\n[GNUPG:] VALIDSIG '"$fpr "* ]]; then
		echo "${file##*/} isn't validly signed by $fpr; not installing it." >&2
		exit 1
	fi
)

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

# gum_release <dir>: installs gum's pinned release binary into <dir>, checksum-verified.
envsetup::gum_release() {
	local arch asset version sha tmp rc=1
	[[ "$OSTYPE" == linux* ]] || return 1
	case $HOSTTYPE in x86_64 | arm64) arch=$HOSTTYPE ;; aarch64) arch=arm64 ;; armv7*) arch=armv7 ;; *) return 1 ;; esac
	version=$(envsetup::pin gum) && sha=$(envsetup::pin gum "linux-${arch/x86_64/amd64}") || return 1
	# versions.txt names gum's Linux_x86_64 linux-amd64.
	asset=gum_${version}_Linux_$arch.tar.gz
	tmp=$(mktemp -d)
	if envsetup::fetch "https://github.com/charmbracelet/gum/releases/download/v$version/$asset" "$tmp/$asset" &&
		echo "$sha  $tmp/$asset" | sha256sum -c >/dev/null &&
		tar -xzf "$tmp/$asset" -C "$tmp" && mkdir -p "$1" &&
		install -m 0755 "$tmp/${asset%.tar.gz}/gum" "$1/gum"; then
		echo "Installed gum $version to $1" >&2
		rc=0
	fi
	rm -rf "$tmp"
	return "$rc"
}

# ensure_gum: the menu needs it. The release binary in ~/.local/bin needs no sudo and
# works on any distro; Homebrew is used when it's there, Go as a last resort.
envsetup::ensure_gum() {
	local bin=$HOME/.local/bin manager need=()
	[[ ":$PATH:" == *":$bin:"* || ! -x "$bin/gum" ]] || PATH=$bin:$PATH
	envsetup::has_cmd gum && return 0
	echo "gum not found, attempting to install it..." >&2
	if envsetup::has_cmd brew; then
		brew install gum
	else
		# Minimal images (Amazon Linux, Leap) can lack tar or gzip, which tar runs to unpack
		# .tar.gz; some have neither curl nor wget.
		envsetup::has_cmd curl || envsetup::has_cmd wget || need+=(curl)
		envsetup::has_cmd tar || need+=(tar)
		envsetup::has_cmd gzip || need+=(gzip)
		if ((${#need[@]})); then
			manager=$(envsetup::pkg_manager)
			if [[ -n "$manager" ]]; then envsetup::pkg_install "$manager" "${need[@]}"; fi
		fi
		if envsetup::gum_release "$bin"; then
			PATH=$bin:$PATH
		elif envsetup::has_cmd go; then
			go install "github.com/charmbracelet/gum@v$(envsetup::pin gum)"
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
	local manager=$1 pkg name i prefix="" failed=() install=() pkgs=() names=()
	shift
	(($#)) || return 0
	case "$manager" in
	brew) install=(brew install) ;;
	apt)
		# Once per setup.sh session: its steps and installers share ENVSETUP_TMP.
		if [[ ! -e "${ENVSETUP_TMP:-}/apt-updated" ]]; then
			# One broken source (e.g. a dead PPA) makes update exit non-zero even though the
			# rest refreshed; install anyway; it still fails loudly if the lists are unusable.
			envsetup::as_root apt-get update || echo "apt-get update reported errors; installing anyway." >&2
			if [[ -n "${ENVSETUP_TMP:-}" ]]; then : >"$ENVSETUP_TMP/apt-updated"; fi
		fi
		# Through env: sudo drops DEBIAN_FRONTEND, and a debconf prompt (tzdata) would hang.
		install=(envsetup::as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y)
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
	for pkg; do
		name=$(envsetup::pkg_name "$manager" "$pkg")
		if [[ -z "$name" ]]; then
			echo "Skipping $pkg: nothing to install for it with $manager." >&2
		else
			pkgs+=("$pkg") names+=("$prefix$name")
		fi
	done
	((${#names[@]})) || return 0
	"${install[@]}" "${names[@]}" && return 0
	# One package the system can't take (a conflict, a name this distro doesn't use)
	# fails the whole batch, so find it by installing them one at a time.
	echo "Installing them one at a time instead..." >&2
	for i in "${!names[@]}"; do
		"${install[@]}" "${names[i]}" || failed+=("${pkgs[i]}")
	done
	((${#failed[@]} == 0)) && return 0
	echo "Couldn't install: ${failed[*]}" >&2
	return 1
}
