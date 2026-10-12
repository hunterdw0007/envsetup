# shellcheck shell=bash
# This file sets ENVSETUP_STATE: the directory where envsetup keeps its settings
# (profile, mode, config.sh) and the files that it makes. shell/init.sh and
# lib/common.sh both use this file. Thus they always use the same directory.
#
# The rc block exports ENVSETUP_STATE with the directory that setup used, and this file
# keeps that value. Thus each shell uses the same directory, also when XDG_CONFIG_HOME
# is set only in some shells (for example in the desktop session, but not over ssh).
#
# Without that value, the directory is $XDG_CONFIG_HOME/envsetup, or ~/.config/envsetup
# if XDG_CONFIG_HOME is not set. The XDG specification tells programs not to use a
# relative XDG_CONFIG_HOME, so this file does not use it. If ~/.config/envsetup is there
# and the new directory is not there, envsetup continues to use ~/.config/envsetup. Thus
# current settings stay in use.
if [[ -z "${ENVSETUP_STATE:-}" ]]; then
	if [[ "${XDG_CONFIG_HOME:-}" == /* ]]; then
		ENVSETUP_STATE=$XDG_CONFIG_HOME/envsetup
	else
		ENVSETUP_STATE=$HOME/.config/envsetup
	fi
	if [[ ! -d "$ENVSETUP_STATE" && -d "$HOME/.config/envsetup" ]]; then ENVSETUP_STATE=$HOME/.config/envsetup; fi
fi
