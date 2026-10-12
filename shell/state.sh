# shellcheck shell=bash
# This file sets ENVSETUP_STATE: the directory where envsetup keeps its settings
# (profile, mode, config.sh) and the files that it makes. The directory is
# $XDG_CONFIG_HOME/envsetup. If XDG_CONFIG_HOME is not set, it is ~/.config/envsetup.
# shell/init.sh and lib/common.sh both use this file. Thus they always use the same
# directory.
#
# The XDG specification tells programs not to use a relative XDG_CONFIG_HOME, so this
# file does not use it. If ~/.config/envsetup is there and the new directory is not
# there, envsetup continues to use ~/.config/envsetup. Thus current settings stay in use.
if [[ "${XDG_CONFIG_HOME:-}" == /* ]]; then
	ENVSETUP_STATE=$XDG_CONFIG_HOME/envsetup
else
	ENVSETUP_STATE=$HOME/.config/envsetup
fi
if [[ ! -d "$ENVSETUP_STATE" && -d "$HOME/.config/envsetup" ]]; then ENVSETUP_STATE=$HOME/.config/envsetup; fi
