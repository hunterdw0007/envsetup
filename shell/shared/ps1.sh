# shellcheck shell=bash
# Prompt loaded on every machine, regardless of profile/mode. Bash only: zsh uses
# different prompt escapes, and on home the oh-my-zsh theme owns the prompt. Not
# exported, so it doesn't leak into child shells that can't read bash escapes.

if [[ -n "${BASH_VERSION:-}" ]]; then
	PS1='\u@\h \W \$ '
fi
