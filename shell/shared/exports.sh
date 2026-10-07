# shellcheck shell=bash
# Environment variables loaded on every machine, regardless of profile.

export XDG_CACHE_HOME="$HOME/.cache"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"
export EDITOR=vim

# Man pages through bat, when it's installed (as `batcat` on Debian/Ubuntu).
for _envsetup_bat in bat batcat; do
	# A real binary: aliases.sh may already have made `bat` an alias, which sh -c can't see.
	[[ "$(command -v "$_envsetup_bat")" == /* ]] || continue
	if [[ "$OSTYPE" == darwin* ]]; then
		# macOS's sed has no \x escapes; its man output is plain overstrikes, which col strips.
		export MANPAGER="sh -c 'col -bx | $_envsetup_bat -p -lman'"
	else
		export MANPAGER="sh -c 'sed -u -e \"s/\\x1B\[[0-9;]*m//g; s/.\\x08//g\" | $_envsetup_bat -p -lman'"
	fi
	break
done
unset _envsetup_bat
