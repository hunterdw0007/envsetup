# shellcheck shell=bash
# This file sets ENVSETUP_STATE.
# That is the folder where envsetup keeps its settings (profile, mode, config.sh).
# envsetup also keeps the files that it makes there.
# shell/init.sh and lib/common.sh both use this file.
# So they always use the same folder.
#
# The startup file block exports ENVSETUP_STATE with the folder that setup used.
# This file keeps that value.
# So each shell uses the same folder, even when only some shells set XDG_CONFIG_HOME.
# For example, the desktop session may set it, but a shell over ssh may not.
# The block also exports ENVSETUP_STATE_HOME, the $HOME that the value belongs to.
# A process with a different $HOME does not keep the value.
# A test with a temporary $HOME is an example.
# So such a process does not use the real state folder.
#
# Without that value, the folder is $XDG_CONFIG_HOME/envsetup.
# If XDG_CONFIG_HOME is not set, the folder is ~/.config/envsetup.
# The XDG specification tells programs to ignore a relative XDG_CONFIG_HOME, so this file ignores it.
# ~/.config/envsetup may exist while the new folder does not.
# Then envsetup keeps using ~/.config/envsetup, so the current settings stay in use.
if [[ -z "${ENVSETUP_STATE:-}" || "${ENVSETUP_STATE_HOME:-}" != "$HOME" ]]; then
	if [[ "${XDG_CONFIG_HOME:-}" == /* ]]; then
		ENVSETUP_STATE=$XDG_CONFIG_HOME/envsetup
	else
		ENVSETUP_STATE=$HOME/.config/envsetup
	fi
	if [[ ! -d "$ENVSETUP_STATE" && -d "$HOME/.config/envsetup" ]]; then ENVSETUP_STATE=$HOME/.config/envsetup; fi
	# The two values stay together, also in child processes when the block exported them.
	ENVSETUP_STATE_HOME=$HOME
fi
