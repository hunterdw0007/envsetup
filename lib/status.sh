#!/usr/bin/env bash
# This file holds "Check status" and setup.sh --status.
# The check reads the machine and changes nothing.
# So it needs no dry-run checks, and it works without gum.
# Each line starts with "ok" or "missing".

# A record of installed tool versions, one "<name> <version>" line per tool.
ENVSETUP_INSTALLED=${XDG_STATE_HOME:-$HOME/.local/state}/envsetup/installed

# status_line <ok|missing> <text> prints one line and counts each missing line.
envsetup::status_line() {
	printf '%-8s %s\n' "$1" "$2"
	if [[ "$1" == missing ]]; then ENVSETUP_STATUS_MISSING=$((ENVSETUP_STATUS_MISSING + 1)); fi
}

# newest_release prints the newest release tag in the envsetup repo.
# It prints nothing when the repo is out of reach, for example offline.
envsetup::newest_release() {
	local url=${ENVSETUP_REPO_URL:-https://github.com/hunterdw0007/envsetup.git}
	GIT_TERMINAL_PROMPT=0 timeout 10 git ls-remote --tags --refs "$url" 'v*' 2>/dev/null |
		sed -n 's|.*refs/tags/\(v[0-9]*\.[0-9]*\.[0-9]*\)$|\1|p' | sort -V | tail -n 1
}

# pkg_installed <manager> <name> is true if the package manager has the package.
envsetup::pkg_installed() {
	case $1 in
	apt) [[ "$(dpkg-query -W -f='${Status}' "$2" 2>/dev/null)" == "install ok installed" ]] ;;
	dnf | zypper) rpm -q --whatprovides "$2" &>/dev/null ;;
	pacman) pacman -T "$2" &>/dev/null ;;
	apk) apk info -e "$2" &>/dev/null ;;
	brew) brew list "$2" &>/dev/null ;;
	nix) nix-env -q "$2" &>/dev/null || nix profile list 2>/dev/null | grep -qF ".$2" ;;
	*) return 1 ;;
	esac
}

# status prints one line for each part of the setup.
# It sets ENVSETUP_STATUS_MISSING to the number of missing lines.
# It returns 0, so a menu action does not treat a missing part as a failed step.
envsetup::status() {
	local state=${STATE_DIR:-$ENVSETUP_STATE} profile="" mode=full newest rc script cmd name pin record
	local manager pkg line before scripts=() pkgs=()
	local -A recorded=()
	ENVSETUP_STATUS_MISSING=0

	newest=$(envsetup::newest_release) || newest=
	newest="newest release: ${newest:-unknown, GitHub is out of reach}"
	if [[ -f "$ENVSETUP_DATA/version" ]]; then
		envsetup::status_line ok "new shells use $(<"$ENVSETUP_DATA/version") ($newest)"
	else
		envsetup::status_line missing "no copy of shell/ in $ENVSETUP_DATA. Select Link shell config ($newest)"
	fi

	if [[ -f "$state/profile" ]]; then profile=$(<"$state/profile"); fi
	if [[ -f "$state/mode" ]]; then mode=$(<"$state/mode"); fi
	ENVSETUP_CONFIG_WARNED=
	envsetup::load_config "$profile" "$mode" >/dev/null 2>&1
	if [[ -z "$profile" ]]; then
		envsetup::status_line missing "no saved profile. Select a profile in the menu"
	elif [[ "$profile" == work ]]; then
		envsetup::status_line ok "profile: work ($mode)"
	else
		envsetup::status_line ok "profile: $profile"
	fi

	for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
		if [[ "$rc" == */.zshrc && "${SHELL##*/}" != zsh && "$ENVSETUP_SHELL" != zsh ]]; then continue; fi
		if [[ -f "$rc" ]] && grep -qF "$ENVSETUP_RC_BEGIN" "$rc"; then
			envsetup::status_line ok "$rc has the envsetup block"
		else
			envsetup::status_line missing "$rc has no envsetup block. Select Link shell config"
		fi
	done

	if envsetup::git_included; then
		envsetup::status_line ok "$HOME/.gitconfig includes $ENVSETUP_GIT_GENERATED"
	else
		envsetup::status_line missing "$HOME/.gitconfig does not include $ENVSETUP_GIT_GENERATED. Select Configure git"
	fi

	# Work lite installs nothing, and without a profile nothing is chosen yet.
	if [[ -n "$profile" ]] && ! envsetup::lite; then
		manager=$(envsetup::pkg_manager 2>/dev/null)
		readarray -t pkgs < <(envsetup::resolved_packages)
		before=$ENVSETUP_STATUS_MISSING
		if [[ -z "$manager" ]]; then
			envsetup::status_line missing "no supported package manager, so envsetup cannot check ${#pkgs[@]} packages"
		else
			for pkg in "${pkgs[@]}"; do
				name=$(envsetup::pkg_name "$manager" "$pkg")
				if [[ -n "$name" ]] && ! envsetup::pkg_installed "$manager" "$name"; then
					envsetup::status_line missing "package $pkg is not installed. Select Install packages"
				fi
			done
		fi
		if ((before == ENVSETUP_STATUS_MISSING)); then envsetup::status_line ok "all ${#pkgs[@]} packages are installed"; fi

		if [[ -f "$ENVSETUP_INSTALLED" ]]; then
			while read -r name record; do
				if [[ -n "$name" ]]; then recorded[$name]=$record; fi
			done <"$ENVSETUP_INSTALLED"
		fi
		readarray -t scripts < <(envsetup::resolved_installers 2>/dev/null)
		before=$ENVSETUP_STATUS_MISSING
		for script in "${scripts[@]}"; do
			name=${script##*/}
			name=${name%.sh}
			# Each installer starts with "envsetup::has_cmd <command> && exit 0" (see AGENTS.md).
			cmd=$name
			while read -r line; do
				if [[ "$line" =~ ^envsetup::has_cmd\ ([^ ]+)\ \&\&\ exit\ 0 ]]; then cmd=${BASH_REMATCH[1]}; fi
			done <"$script"
			record=${recorded[$name]:-}
			pin=$(envsetup::pin "$name" 2>/dev/null) || pin=
			if ! envsetup::has_cmd "$cmd"; then
				envsetup::status_line missing "$cmd is not on PATH. Select Run installers"
			elif [[ -n "$record" && -n "$pin" && "$record" != "$pin" &&
				"$(printf '%s\n' "$record" "$pin" | sort -V | head -n 1)" == "$record" ]]; then
				envsetup::status_line missing "$name $record is older than the pinned $pin"
			fi
		done
		if ((before == ENVSETUP_STATUS_MISSING)); then envsetup::status_line ok "all ${#scripts[@]} installer tools are on PATH"; fi
	fi

	if [[ -n "$ENVSETUP_CONFIG_WARNED" ]]; then
		envsetup::status_line missing "$ENVSETUP_CONFIG_WARNED"
	elif [[ -f "$ENVSETUP_USER_CONFIG" ]]; then
		envsetup::status_line ok "$ENVSETUP_USER_CONFIG loads without errors"
	else
		envsetup::status_line ok "no $ENVSETUP_USER_CONFIG, so envsetup uses its defaults"
	fi
}
