# shellcheck shell=bash
# Every machine loads the envsetup command, in every profile and mode, in bash and zsh.
# envsetup deletes its download after each run.
# So this command runs the curl command from the README again.
# install.sh then downloads a release and runs setup.sh from it.

envsetup() {
	local url=https://raw.githubusercontent.com/hunterdw0007/envsetup/main/install.sh script
	local version=${ENVSETUP_VERSION:-}
	case ${1:-} in
	-h | --help | help)
		cat <<'EOF'
Usage: envsetup [command] [setup.sh options]

Commands:
  update     download the newest release and open the menu (the default)
  status     show what envsetup set up (setup.sh --status), with the
             release that your shells use
  config     open config.sh in $EDITOR and check it, like "Edit config"
             (setup.sh --edit-config)
  uninstall  remove what envsetup added (setup.sh --uninstall)
  version    show the release that your shells use

Other options go to setup.sh. For example, envsetup --dry-run opens the menu
but changes nothing. ENVSETUP_REPO_URL and ENVSETUP_VERSION work as in the
curl command.
EOF
		;;
	version) cat "$ENVSETUP_ROOT/version" ;;
	'' | update | status | config | uninstall | -*)
		case ${1:-} in
		update) shift ;;
		uninstall) set -- --uninstall "${@:2}" ;;
		status | config)
			if [[ $1 == status ]]; then set -- --status "${@:2}"; else set -- --edit-config "${@:2}"; fi
			# Use the release that the shells use, not the newest one.
			if [[ -z "$version" && -f "$ENVSETUP_ROOT/version" ]]; then version=$(<"$ENVSETUP_ROOT/version"); fi
			;;
		esac
		# An interactive shell has no pipefail, so `curl | bash` would hide a failed download.
		script=$(curl -fsSL "$url") || {
			echo "envsetup: could not download $url" >&2
			return 1
		}
		# config.sh may set ENVSETUP_REPO_URL without export, so pass it on here.
		ENVSETUP_REPO_URL="${ENVSETUP_REPO_URL:-}" ENVSETUP_VERSION="$version" bash -c "$script" install.sh "$@"
		;;
	*)
		echo "envsetup: unknown command: $1 (see envsetup --help)" >&2
		return 2
		;;
	esac
}
