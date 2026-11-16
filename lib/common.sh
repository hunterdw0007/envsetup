#!/usr/bin/env bash
# Helpers that the envsetup scripts share.
# shellcheck disable=SC2034 # the other lib files use the ENVSETUP_* constants

# shellcheck source=shell/state.sh
source "$ENVSETUP_ROOT/shell/state.sh"
ENVSETUP_RC_BEGIN="# >>> envsetup >>>"
ENVSETUP_RC_END="# <<< envsetup <<<"
ENVSETUP_CHSH_MARKER="$ENVSETUP_STATE/chsh"       # exists after envsetup changes your login shell to zsh
ENVSETUP_SSH_KEY_MARKER="$ENVSETUP_STATE/ssh-key" # exists after envsetup creates ~/.ssh/id_ed25519
ENVSETUP_SHELL_D="$ENVSETUP_STATE/shell.d"        # your own shell files, which shell/init.sh loads
# New shells load this copy of shell/ (see copyShell in internal/setup/link.go).
# The copy's release is recorded next to it.
ENVSETUP_DATA=$HOME/.local/share/envsetup
if [[ "${XDG_DATA_HOME:-}" == /* ]]; then ENVSETUP_DATA=$XDG_DATA_HOME/envsetup; fi

envsetup::has_cmd() { command -v "$1" &>/dev/null; }

# as_root runs a command as root.
# If the user is already root, it runs the command directly (containers, WSL).
# Otherwise it uses sudo, or doas (Alpine).
envsetup::as_root() {
	if ((EUID == 0)); then
		"$@"
	elif envsetup::has_cmd sudo; then
		sudo "$@"
	elif envsetup::has_cmd doas; then
		doas "$@"
	else
		echo "This command needs root, but this machine has no sudo or doas: $*" >&2
		return 1
	fi
}

# os_release <KEY> prints a field of /etc/os-release.
# Examples are ID=rocky and ID_LIKE="rhel centos fedora".
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

# arch prints amd64 or arm64, the names that most release downloads use.
envsetup::arch() {
	case $HOSTTYPE in
	x86_64) echo amd64 ;;
	aarch64) echo arm64 ;;
	*) echo "$HOSTTYPE" ;;
	esac
}

# Some systems mount /usr as read-only: Silverblue, Bazzite, SteamOS and Aeon/MicroOS.
# So their own package manager cannot install into the running system.
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

# pin <name> prints the version of <name> from installers/versions.txt.
# pin <name> <platform> prints the sha256 of that platform's download instead.
# <platform> is a key in that file, for example linux-amd64.
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

# The installers record each tool that they install, one "<name> <version>" line per tool.
# The name is the installer's name, which is also its name in installers/versions.txt.
# The XDG specification tells programs to ignore a relative XDG_STATE_HOME, so this file ignores it.
ENVSETUP_INSTALLED=$HOME/.local/state/envsetup/installed
if [[ "${XDG_STATE_HOME:-}" == /* ]]; then ENVSETUP_INSTALLED=$XDG_STATE_HOME/envsetup/installed; fi

# installed_version <name> prints the version of <name> that envsetup installed.
# It prints nothing if envsetup did not install <name>.
envsetup::installed_version() {
	local name version
	[[ -r "$ENVSETUP_INSTALLED" ]] || return 0
	while read -r name version; do
		if [[ "$name" == "$1" ]]; then
			echo "$version"
			return 0
		fi
	done <"$ENVSETUP_INSTALLED"
}

# up_to_date <name> <command> succeeds when the installer of <name> has nothing to do.
# That is the case when <command> is on PATH and envsetup did not install it.
# The user installed that tool, so envsetup leaves it alone.
# It is also the case when envsetup installed the pinned version.
envsetup::up_to_date() {
	local had
	envsetup::has_cmd "$2" || return 1
	had=$(envsetup::installed_version "$1")
	[[ -z "$had" || "$had" == "$(envsetup::pin "$1")" ]]
}

# record_installed <name> records the pinned version of <name> in ENVSETUP_INSTALLED.
# It replaces the line of an older version.
envsetup::record_installed() {
	local name version lines=()
	if [[ -f "$ENVSETUP_INSTALLED" ]]; then
		while read -r name version; do
			if [[ "$name" != "$1" ]]; then lines+=("$name $version"); fi
		done <"$ENVSETUP_INSTALLED"
	fi
	version=$(envsetup::pin "$1")
	mkdir -p "${ENVSETUP_INSTALLED%/*}"
	printf '%s\n' "${lines[@]}" "$1 $version" >"$ENVSETUP_INSTALLED"
}

# release_sha256 <checksums url> <file> prints the hash of <file> from a project's sha256 list.
# The list can have "<hash>  <file>" lines, the format of sha256sum.
# It also accepts "*file" and "./file".
# The list can also be a .sha256 file with only one hash.
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

# install_release <url> <sha256> <member>... downloads a release and checks its hash.
# The release can be a .tar.gz, a .zip or a single binary.
# A member is a path inside the archive, or the binary's name.
# The function installs each member into /usr/local/bin under its base name.
envsetup::install_release() (
	url=$1 sha=$2 tmp=$(mktemp -d)
	shift 2
	trap 'rm -rf "$tmp"' EXIT
	file=$tmp/download-${url##*/}
	curl -fsSL -o "$file" "$url"
	if ! echo "$sha  $file" | sha256sum -c >/dev/null 2>&1; then
		echo "${url##*/} does not match its published checksum. envsetup does not install it." >&2
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

# gpg_verify <file> <signature> <key.asc> <fingerprint> checks a separate signature file.
# It checks the signature against a key in this repo.
# It passes only for a valid signature by exactly that key.
# An expired key alone does not fail the check.
# Vendors extend a key's expiry date and keep signing with the same key.
# So the copy in this repo gets old, but the key stays the same.
# Debian and Ubuntu always have gpgv, but often not gpg.
# gpgv reads only binary keyrings, so the function converts the text key first.
envsetup::gpg_verify() (
	file=$1 sig=$2 key=$3 fpr=$4 tmp=$(mktemp -d) body=false status=
	trap 'rm -rf "$tmp"' EXIT
	while IFS= read -r line; do
		[[ $line == -----END* ]] && break
		if $body; then
			[[ $line == =* ]] || printf '%s\n' "$line" # skip the checksum line of the text key
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
		echo "envsetup needs gpgv or gpg to check the signature of ${file##*/}. Install gnupg." >&2
		exit 1
	fi
	if [[ $'\n'"$status" != *$'\n[GNUPG:] VALIDSIG '"$fpr "* ]]; then
		echo "${file##*/} has no valid signature by $fpr. envsetup does not install it." >&2
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
		echo "/usr is read-only on this system (Silverblue, Bazzite, SteamOS, MicroOS, ...). So the system's package manager cannot install anything. Install Homebrew (https://brew.sh), then run envsetup again." >&2
	fi
}

# pkg_name <manager> <package> prints the name that <manager> uses for <package>.
# <package> is the name in packages/*.txt, and packages/names.txt holds the other names.
# It prints nothing if that manager needs no package.
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

# fetch <url> <file> downloads with curl or wget.
# Ubuntu's desktop install has only wget.
envsetup::fetch() {
	if envsetup::has_cmd curl; then curl -fsSL -o "$2" "$1"; else wget -qO "$2" "$1"; fi
}

# pkg_install <manager> <package>... installs packages by their names in packages/*.txt.
# pkg_name translates each name for the manager.
envsetup::pkg_install() {
	local manager=$1 pkg name i prefix="" failed=() install=() pkgs=() names=()
	shift
	(($#)) || return 0
	case "$manager" in
	brew) install=(brew install) ;;
	apt)
		# This runs once in each envsetup run.
		# The steps and installers of one run share ENVSETUP_TMP.
		if [[ ! -e "${ENVSETUP_TMP:-}/apt-updated" ]]; then
			# One broken source, such as a removed PPA, makes the update exit non-zero.
			# The other sources still refresh, so the install goes ahead.
			# The install still fails with an error if the lists are broken.
			envsetup::as_root apt-get update || echo "apt-get update reported errors. Installing anyway." >&2
			if [[ -n "${ENVSETUP_TMP:-}" ]]; then : >"$ENVSETUP_TMP/apt-updated"; fi
		fi
		# This passes DEBIAN_FRONTEND through env, because sudo drops it.
		# Without it, a debconf question (tzdata) would wait forever.
		install=(envsetup::as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y)
		;;
	dnf) install=(envsetup::as_root dnf install -y) ;;
	zypper) install=(envsetup::as_root zypper --non-interactive install) ;;
	pacman)
		# A machine that has never synced has no package lists, for example a new container.
		# A sync without an upgrade is a partial upgrade.
		# Arch does not support partial upgrades, so the command uses -u.
		compgen -G '/var/lib/pacman/sync/*.db' >/dev/null || envsetup::as_root pacman -Syu --noconfirm
		install=(envsetup::as_root pacman -S --noconfirm --needed)
		;;
	apk) install=(envsetup::as_root apk add) ;;
	nix)
		# New profiles (nix profile) and classic profiles (nix-env) do not work together.
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
			echo "Skipping $pkg: $manager needs no package for it." >&2
		else
			pkgs+=("$pkg") names+=("$prefix$name")
		fi
	done
	((${#names[@]})) || return 0
	"${install[@]}" "${names[@]}" && return 0
	# One bad package fails the whole install.
	# A conflict, or a name that this distro does not use, are examples.
	# So the function installs the packages one at a time to find the bad one.
	echo "Installing them one at a time instead..." >&2
	for i in "${!names[@]}"; do
		"${install[@]}" "${names[i]}" || failed+=("${pkgs[i]}")
	done
	((${#failed[@]} == 0)) && return 0
	echo "Couldn't install: ${failed[*]}" >&2
	return 1
}
