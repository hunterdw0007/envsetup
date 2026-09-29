# shellcheck shell=bash
# Aliases loaded on every machine, regardless of profile.

alias ll='ls -la'
alias gs='git status'
alias gd='git diff'
alias gc='git commit'
alias gp='git push'

# Debian/Ubuntu install the bat package (packages/common.txt) as `batcat`.
if ! command -v bat >/dev/null && command -v batcat >/dev/null; then
	alias bat=batcat
fi
