#!/usr/bin/env bash
# Your startup file sources this file, through the block that setup.sh adds.
# It loads the shared config first, then the config of the active profile.
# It loads your own config.sh next, so your settings win.
# It loads your own files in shell.d last.

[[ -n "${ENVSETUP_ROOT:-}" ]] || return 0

# shellcheck source=shell/state.sh
source "$ENVSETUP_ROOT/shell/state.sh"
ENVSETUP_PROFILE="" ENVSETUP_MODE=full
[[ -f "$ENVSETUP_STATE/profile" ]] && ENVSETUP_PROFILE="$(<"$ENVSETUP_STATE/profile")"
[[ "$ENVSETUP_PROFILE" == work && -f "$ENVSETUP_STATE/mode" ]] && ENVSETUP_MODE="$(<"$ENVSETUP_STATE/mode")"

# Every shell gets the following, interactive or not (`ssh host cmd`, scp, rsync, scripts).
# It gets the exports, except on work lite.
# For example, `ssh host git commit` needs EDITOR.
# It also gets the exports for dotfiles that "Move dotfiles to XDG dirs" moved.
# Without them, the programs would create the dotfiles in $HOME again.
# None of these files print anything or run a program.
# So commands over ssh stay fast, and scp's silent remote shell stays silent.
# shellcheck source=shell/shared/exports.sh
[[ "$ENVSETUP_MODE" == lite ]] || source "$ENVSETUP_ROOT/shell/shared/exports.sh"
# shellcheck source=/dev/null # lib/xdg.sh generates this file
[[ -f "$ENVSETUP_STATE/xdg.sh" ]] && source "$ENVSETUP_STATE/xdg.sh"

# The rest is only for interactive shells.
# Some distros' ~/.bashrc does not return early for non-interactive shells (Fedora's).
# work lite does not assume sudo.
# So it gets only the prompt, the aliases, the envsetup command and the hooks for tools that are installed.
if [[ $- == *i* ]]; then
	_envsetup_files=(ps1 aliases tools envsetup)
	[[ "$ENVSETUP_MODE" == lite ]] || _envsetup_files+=(functions)
	for _envsetup_f in "${_envsetup_files[@]}"; do
		# shellcheck disable=SC1090 # the path is known only at runtime
		source "$ENVSETUP_ROOT/shell/shared/$_envsetup_f.sh"
	done
	if [[ -n "$ENVSETUP_PROFILE" ]]; then
		for _envsetup_f in "$ENVSETUP_ROOT/shell/profiles/$ENVSETUP_PROFILE"/*.sh; do
			# shellcheck disable=SC1090
			[[ -f "$_envsetup_f" ]] && source "$_envsetup_f"
		done
	fi
fi
# config.sh loads in every shell, and it loads last, so it wins.
# Code in it for interactive shells only goes under [[ $- == *i* ]] (see config.example.sh).
# shellcheck source=/dev/null # the user's own file
[[ -f "$ENVSETUP_STATE/config.sh" ]] && source "$ENVSETUP_STATE/config.sh"

# Your own shell files in shell.d load after config.sh, in name order, in interactive shells only.
# Files that end in .sh load in bash and zsh.
# Files that end in .bash or .zsh load only in that shell.
# This file skips all other files, such as a README or a backup.
if [[ $- == *i* ]]; then
	_envsetup_ext=bash
	if [[ -n "${ZSH_VERSION:-}" ]]; then
		_envsetup_ext=zsh
		# (N) makes an empty folder match nothing.
		# Without it, zsh stops this file with an error.
		# bash cannot parse (N), so eval hides it from bash.
		eval '_envsetup_files=("$ENVSETUP_STATE/shell.d"/*(N))'
	else
		_envsetup_files=("$ENVSETUP_STATE/shell.d"/*)
	fi
	for _envsetup_f in "${_envsetup_files[@]}"; do
		if [[ -f "$_envsetup_f" && ("$_envsetup_f" == *.sh || "$_envsetup_f" == *."$_envsetup_ext") ]]; then
			# shellcheck disable=SC1090 # the user's own files
			source "$_envsetup_f"
		fi
	done
fi

unset _envsetup_files _envsetup_f _envsetup_ext
