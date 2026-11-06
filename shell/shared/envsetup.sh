# shellcheck shell=bash
# Every machine loads the envsetup command, in every profile and mode, in bash and zsh.
# envsetup deletes its download after each run.
# So this command runs the curl command from the README again.
# install.sh then downloads a release and runs setup.sh from it.

envsetup() {
	local url=https://raw.githubusercontent.com/hunterdw0007/envsetup/main/install.sh
	case ${1:-} in
	-h | --help | help)
		cat <<'EOF'
Usage: envsetup [command] [setup.sh options]

Commands:
  update     download the newest release and open the menu (the default)
  status     show what envsetup set up (setup.sh --status)
  config     open config.sh in $EDITOR
  uninstall  remove what envsetup added (setup.sh --uninstall)
  version    show the release that your shells use

Other options go to setup.sh. For example, envsetup --dry-run opens the menu
but changes nothing. ENVSETUP_REPO_URL and ENVSETUP_VERSION work as in the
curl command.
EOF
		;;
	version) cat "$ENVSETUP_ROOT/version" ;;
	config) "${EDITOR:-vi}" "$ENVSETUP_STATE/config.sh" ;;
	'' | update | status | uninstall | -*)
		case ${1:-} in
		update) shift ;;
		status | uninstall) set -- "--$1" "${@:2}" ;;
		esac
		# config.sh may set ENVSETUP_REPO_URL without export, so pass it on here.
		curl -fsSL "$url" | ENVSETUP_REPO_URL="${ENVSETUP_REPO_URL:-}" bash -s -- "$@"
		;;
	*)
		echo "envsetup: unknown command: $1 (see envsetup --help)" >&2
		return 2
		;;
	esac
}
