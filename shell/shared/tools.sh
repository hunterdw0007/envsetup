# shellcheck shell=bash
# Shell hooks for tools that only work once the shell knows about them, each only when
# the tool is installed: direnv (per-directory .envrc), zoxide (`z`), fzf's key
# bindings (Ctrl-R history, Ctrl-T files, Alt-C cd) and mise (per-project runtimes).
# Loaded in bash and zsh, on every profile and mode.

_envsetup_sh=bash
[[ -n "${ZSH_VERSION:-}" ]] && _envsetup_sh=zsh

# Homebrew (macOS, some Linux setups) installs outside the default PATH; without this, a
# shell that wasn't set up for it can't see brew or anything it installed.
if ! command -v brew >/dev/null; then
	for _envsetup_f in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
		if [[ -x "$_envsetup_f" ]]; then
			eval "$("$_envsetup_f" shellenv)"
			break
		fi
	done
fi

if command -v direnv >/dev/null; then eval "$(direnv hook "$_envsetup_sh")"; fi
if command -v zoxide >/dev/null; then eval "$(zoxide init "$_envsetup_sh")"; fi
if command -v mise >/dev/null; then eval "$(mise activate "$_envsetup_sh")"; fi

# fzf 0.48+ prints its own bindings; older ones (Ubuntu 22.04 and 24.04, Debian 12) ship
# a file whose path differs by distro. Key bindings need a terminal (zsh's zle errors
# without one).
if command -v fzf >/dev/null && [[ -t 0 ]]; then
	if _envsetup_f=$(fzf "--$_envsetup_sh" 2>/dev/null); then
		eval "$_envsetup_f"
	else
		for _envsetup_f in /usr/share/doc/fzf/examples /usr/share/fzf/shell /usr/share/fzf; do
			if [[ -f "$_envsetup_f/key-bindings.$_envsetup_sh" ]]; then
				# shellcheck source=/dev/null # distro file
				source "$_envsetup_f/key-bindings.$_envsetup_sh"
				break
			fi
		done
	fi
fi

# Debian and Ubuntu install fd as fdfind (fd was taken).
if ! command -v fd >/dev/null && command -v fdfind >/dev/null; then alias fd=fdfind; fi

unset _envsetup_sh _envsetup_f
