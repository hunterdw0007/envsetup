# shellcheck shell=bash
# Every machine loads these aliases, in every profile and mode.
# The git short commands are git aliases in git/gitconfig (git s, git d, git l, ...).
# They are not shell aliases.

alias ls='ls --color=auto'
alias la='ls -a'
alias ll='ls -alh'

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# cat and less use bat (packages/common.txt), but only when bat is installed.
# Debian and Ubuntu install bat as `batcat`.
# work lite installs nothing.
# A cat alias to a missing command would break cat itself.
for _envsetup_bat in bat batcat; do
	[[ "$(command -v "$_envsetup_bat")" == /* ]] || continue # a real binary, not an alias
	[[ "$_envsetup_bat" == batcat ]] && alias bat=batcat
	# shellcheck disable=SC2139 # this expands now on purpose, to the name that exists
	alias cat="$_envsetup_bat" less="$_envsetup_bat --paging=always"
	break
done
unset _envsetup_bat
