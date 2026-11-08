# shellcheck shell=bash
# Every machine loads these environment variables, in every profile.
# Each value is only a default.
# If a variable already has a value, this file does not change it.
# ~/.profile, the startup file before this file, or the desktop session may set the value.

export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
# A machine without vim gets no EDITOR, so git and Edit config use their own fallback.
if [[ -z "${EDITOR:-}" ]] && command -v vim >/dev/null; then export EDITOR=vim; fi

# Man pages use bat when bat is installed.
# Debian and Ubuntu install bat as `batcat`.
# If MANPAGER already has a value, this file does not change it.
for _envsetup_bat in bat batcat; do
	[[ -z "${MANPAGER:-}" ]] || break
	# Use the real program.
	# aliases.sh may already have made `bat` an alias, and sh -c cannot see aliases.
	[[ "$(command -v "$_envsetup_bat")" == /* ]] || continue
	export MANPAGER="sh -c 'sed -u -e \"s/\\x1B\[[0-9;]*m//g; s/.\\x08//g\" | $_envsetup_bat -p -lman'"
	break
done
unset _envsetup_bat
