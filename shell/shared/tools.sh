# shellcheck shell=bash
# Some tools work only after the shell loads their hook.
# This file loads the hook for each of these tools that is installed:
#   - direnv: loads the .envrc file of each folder
#   - zoxide: adds `z`
#   - fzf: adds key bindings (Ctrl-R history, Ctrl-T files, Alt-C cd)
#   - mise: sets the runtime versions for each project
# bash and zsh load this file, in every profile and mode.

_envsetup_sh=bash
[[ -n "${ZSH_VERSION:-}" ]] && _envsetup_sh=zsh

if command -v direnv >/dev/null; then eval "$(direnv hook "$_envsetup_sh")"; fi
if command -v zoxide >/dev/null; then eval "$(zoxide init "$_envsetup_sh")"; fi
if command -v mise >/dev/null; then eval "$(mise activate "$_envsetup_sh")"; fi

# fzf 0.48 and newer prints its own key bindings.
# Older versions (Ubuntu 22.04 and 24.04, Debian 12) include a file instead.
# The path of that file differs by distro.
# Key bindings need a terminal, because zsh's zle fails without one.
if command -v fzf >/dev/null && [[ -t 0 ]]; then
	if _envsetup_f=$(fzf "--$_envsetup_sh" 2>/dev/null); then
		eval "$_envsetup_f"
	else
		for _envsetup_f in /usr/share/doc/fzf/examples /usr/share/fzf/shell /usr/share/fzf; do
			if [[ -f "$_envsetup_f/key-bindings.$_envsetup_sh" ]]; then
				# shellcheck source=/dev/null # a file from the distro
				source "$_envsetup_f/key-bindings.$_envsetup_sh"
				break
			fi
		done
	fi
fi

# Debian and Ubuntu install fd as fdfind, because another package already uses the name fd.
if ! command -v fd >/dev/null && command -v fdfind >/dev/null; then alias fd=fdfind; fi

unset _envsetup_sh _envsetup_f
