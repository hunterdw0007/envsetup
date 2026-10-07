# shellcheck shell=bash
# Aliases loaded on every machine, regardless of profile/mode. Git shortcuts are git
# aliases in git/gitconfig (git s, git d, git l, ...), not shell aliases.

# macOS's (BSD) ls colors with -G; GNU's --color would be an error there.
if [[ "$OSTYPE" == darwin* ]]; then alias ls='ls -G'; else alias ls='ls --color=auto'; fi
alias la='ls -a'
alias ll='ls -alh'

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# cat/less through bat (packages/common.txt; installed as `batcat` on Debian/Ubuntu),
# only when it's there: work lite installs nothing, and a cat alias to a missing
# command would break cat itself.
for _envsetup_bat in bat batcat; do
	[[ "$(command -v "$_envsetup_bat")" == /* ]] || continue # a real binary, not an alias
	[[ "$_envsetup_bat" == batcat ]] && alias bat=batcat
	# shellcheck disable=SC2139 # expanded now on purpose: whichever name exists
	alias cat="$_envsetup_bat" less="$_envsetup_bat --paging=always"
	break
done
unset _envsetup_bat
