# shellcheck shell=bash
# Homebrew installs outside macOS's default PATH (/opt/homebrew on Apple silicon), so a
# shell that wasn't set up for it can't see brew or anything it installed. Only on macOS:
# a Homebrew on Linux that's kept off PATH stays off. shell/init.sh loads this first
# (aliases.sh looks for brew's tools), and envsetup::brew_shellenv runs it for setup.sh,
# under bash 3.2. install.sh has a copy, since nothing is cloned yet when it runs.
if [[ "$OSTYPE" == darwin* ]] && ! command -v brew >/dev/null; then
	for _envsetup_brew in /opt/homebrew/bin/brew /usr/local/bin/brew; do
		if [[ -x "$_envsetup_brew" ]]; then
			eval "$("$_envsetup_brew" shellenv)"
			break
		fi
	done
	unset _envsetup_brew
fi
