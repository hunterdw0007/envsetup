# shellcheck shell=bash
# Environment variables loaded on every machine, regardless of profile. Each value is
# only a default. If a value is already set (in ~/.profile, in the rc file before this
# file, or by the desktop session), this file does not change it.

export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export EDITOR="${EDITOR:-vim}"

# Man pages through bat, when it's installed (as `batcat` on Debian/Ubuntu). If MANPAGER
# is already set, this file does not change it.
for _envsetup_bat in bat batcat; do
	[[ -z "${MANPAGER:-}" ]] || break
	# A real binary: aliases.sh may already have made `bat` an alias, which sh -c can't see.
	[[ "$(command -v "$_envsetup_bat")" == /* ]] || continue
	export MANPAGER="sh -c 'sed -u -e \"s/\\x1B\[[0-9;]*m//g; s/.\\x08//g\" | $_envsetup_bat -p -lman'"
	break
done
unset _envsetup_bat
