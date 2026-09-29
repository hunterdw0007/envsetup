#!/usr/bin/env bash
# Smoke test: runs envsetup for real on a bare Ubuntu box. Only the slow or networked
# edges are stubbed (gum's UI, package installs, vendor downloads); install.sh's git
# bootstrap, the clone, setup.sh's menu flow, rc-file linking, and a real bash and zsh
# loading the result are all real.
#
#   docker run --rm -t -v "$PWD:/src:ro" ubuntu:24.04 bash /src/tests/smoke.sh
#
# Needs a TTY (-t: install.sh hands off to setup.sh via /dev/tty) and a throwaway
# container, since it installs git and zsh and writes to /root.
# shellcheck disable=SC2016 # single-quoted code is meant to expand in the stubs / test shells
set -euo pipefail

SRC=/src
CLONE=/root/envsetup
W=/tmp/smoke
STUBS=$W/stubs     # gum + sudo: on PATH for every run
OFFLINE=$W/offline # package manager, curl, chsh, "already installed" vendor tools
export SMOKE_LOG=$W/calls.log SMOKE_CHOICES=$W/choices
failures=0

pass() { printf '  ok    %s\n' "$1"; }
fail() {
	printf '  FAIL  %s\n' "$1"
	failures=$((failures + 1))
}
check() {
	local desc=$1
	shift
	if "$@"; then pass "$desc"; else fail "$desc"; fi
}
has() { command -v "$1" >/dev/null; }
count() { grep -cF -- "$1" "$2" || true; }
not_grep() { ! grep -q -- "$1" "$2"; }
same_list() { [ -n "$1" ] && [ "$1" = "$2" ]; } # an empty expected list is a broken test, not a pass
same_commit() { # both must resolve, so two failed lookups can't compare equal
	local a b
	a=$(git -C "$1" rev-parse --verify -q HEAD) && b=$(git -C "$2" rev-parse --verify -q HEAD) && [ "$a" = "$b" ]
}

{ : </dev/tty; } 2>/dev/null || {
	echo "No TTY: run the container with -t (see the header of this file)." >&2
	exit 2
}

mkdir -p "$STUBS" "$OFFLINE"

# gum: answers `choose` from $SMOKE_CHOICES (one per line; "ESC", or running out,
# cancels), declines `confirm`, fills `input`, and logs every call.
cat >"$STUBS/gum" <<'EOF'
#!/usr/bin/env bash
echo "gum $*" >>"$SMOKE_LOG"
case $1 in
	choose)
		answer=ESC
		read -r answer <"$SMOKE_CHOICES" || true
		sed -i 1d "$SMOKE_CHOICES"
		[[ $answer == ESC ]] && exit 1
		echo "$answer" ;;
	input) [[ $* == *@* ]] && echo smoke@example.com || echo "Smoke Test" ;;
	confirm) exit 1 ;;
	style) echo "${*: -1}" ;;
esac
EOF
# Root in the container; a real machine has sudo.
printf '#!/bin/sh\nexec "$@"\n' >"$STUBS/sudo"

printf '#!/bin/sh\necho "apt-get $*" >>"$SMOKE_LOG"\n' >"$OFFLINE/apt-get"
printf '#!/bin/sh\necho "chsh $*" >>"$SMOKE_LOG"\n' >"$OFFLINE/chsh"
# curl only serves a stand-in oh-my-zsh installer; any other download is a test bug.
cat >"$OFFLINE/curl" <<'EOF'
#!/bin/sh
echo "curl $*" >>"$SMOKE_LOG"
case "$*" in
	*ohmyzsh*) cat <<'OMZ' ;;
mkdir -p "$HOME/.oh-my-zsh"
[ -f "$HOME/.zshrc" ] || echo 'PROMPT="%n@%m %# "  # stand-in for the oh-my-zsh theme' >"$HOME/.zshrc"
OMZ
	*) echo "smoke: unexpected download: curl $*" >&2; exit 1 ;;
esac
EOF
for tool in kubectl helm gh terraform aws; do printf '#!/bin/sh\n' >"$OFFLINE/$tool"; done
chmod +x "$STUBS"/* "$OFFLINE"/*

# run_menu <home> <answers...>: runs the cloned setup.sh offline, answering the menu.
run_menu() {
	local home=$1
	shift
	printf '%s\n' "$@" >"$SMOKE_CHOICES"
	: >"$SMOKE_LOG"
	HOME=$home PATH="$OFFLINE:$STUBS:$PATH" "$CLONE/setup.sh" >"$home/setup.out" 2>&1 </dev/tty
}
new_home() {
	local h
	h=$(mktemp -d)
	cp -rT /etc/skel "$h"
	echo "$h"
}
show() { sed 's/^/        | /' "$1"; }
installed() { sed -n 's/^apt-get install -y //p' "$SMOKE_LOG" | tr ' ' '\n' | sort -u; }
expected() { grep -hvE '^\s*(#|$)' "$CLONE/packages/common.txt" "$CLONE/packages/$1.txt" | sort -u; }
# in_shell <home> <bash|zsh> <cmd>: runs cmd in a real interactive shell that loads
# the linked rc file; stderr (minus no-TTY job-control notices) goes to <home>/shell.err.
in_shell() {
	local out
	out=$(HOME=$1 setsid "$2" -i -c "$3" 2>"$1/shell.raw" </dev/null)
	grep -vE 'job control|terminal process group|pgrp' "$1/shell.raw" >"$1/shell.err" || true
	echo "$out"
}

echo "== install.sh on a bare box: real apt for git, real clone, hand-off to setup.sh"
printf '[safe]\n\tdirectory = *\n' >"$HOME/.gitconfig" # /src is owned by the host's user
printf 'Quit\n' >"$SMOKE_CHOICES"
: >"$SMOKE_LOG"
if PATH="$STUBS:$PATH" ENVSETUP_REPO_URL=$SRC ENVSETUP_DIR=$CLONE bash "$SRC/install.sh" >$W/install.out 2>&1; then
	pass "install.sh exited 0"
else
	fail "install.sh exited non-zero"
	show $W/install.out
fi
check "git was installed" has git
check "cloned the commit under test" same_commit "$SRC" "$CLONE"
check "setup.sh reached the menu on a first run" grep -q '^gum choose Select profile (current: none)' "$SMOKE_LOG"

# Real zsh, so the home profile's shell config is checked in the shell it targets.
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq zsh >$W/zsh.out 2>&1 || {
	show $W/zsh.out
	exit 1
}

echo "== work/full: Run everything"
h=$(new_home)
if run_menu "$h" "Select profile" work full "Run everything" Quit; then pass "exited 0"; else fail "exited non-zero"; fi
check "linked ~/.bashrc once" [ "$(count '# >>> envsetup >>>' "$h/.bashrc")" = 1 ]
check "installed common + work packages" same_list "$(expected work)" "$(installed)"
for s in "$CLONE"/installers/work/*.sh; do
	check "ran installer ${s##*/}" grep -qF "Running ${s##*/}" "$SMOKE_LOG"
done
check "no downloads (vendor tools already installed)" not_grep '^curl ' "$SMOKE_LOG"
check "bash loads the aliases" [ "$(in_shell "$h" bash 'alias ll')" = "alias ll='ls -la'" ]
check "bash gets the prompt" [ "$(in_shell "$h" bash 'printf %s "$PS1"')" = '\u@\h \W \$ ' ]
check "bash starts without errors" [ ! -s "$h/shell.err" ]
[ -s "$h/shell.err" ] && show "$h/shell.err"
if run_menu "$h" "Run everything" Quit; then pass "re-run exited 0"; else fail "re-run exited non-zero"; fi
check "re-run didn't link twice" [ "$(count '# >>> envsetup >>>' "$h/.bashrc")" = 1 ]
((failures)) && show "$h/setup.out"

echo "== work/lite: Run everything (no sudo: no packages, no installers)"
h=$(new_home)
if run_menu "$h" "Select profile" work lite "Run everything" Quit; then pass "exited 0"; else fail "exited non-zero"; fi
check "linked ~/.bashrc" grep -qF '# >>> envsetup >>>' "$h/.bashrc"
check "no package installs" [ "$(count 'apt-get' "$SMOKE_LOG")" = 0 ]
check "no installers run" [ "$(count 'Running ' "$SMOKE_LOG")" = 0 ]
check "bash loads the aliases" [ "$(in_shell "$h" bash 'alias ll')" = "alias ll='ls -la'" ]
check "bash skips exports" [ -z "$(in_shell "$h" bash 'printf %s "${EDITOR:-}"')" ]

echo "== home: Run everything (zsh + oh-my-zsh)"
h=$(new_home)
if run_menu "$h" "Select profile" home "Run everything" Quit; then pass "exited 0"; else fail "exited non-zero"; fi
check "installed oh-my-zsh" [ -d "$h/.oh-my-zsh" ]
check "kept the oh-my-zsh .zshrc" grep -qF 'stand-in for the oh-my-zsh theme' "$h/.zshrc"
check "linked ~/.zshrc once" [ "$(count '# >>> envsetup >>>' "$h/.zshrc")" = 1 ]
check "installed common + home packages" same_list "$(expected home)" "$(installed)"
check "zsh loads the aliases" [ "$(in_shell "$h" zsh 'alias ll')" = "ll='ls -la'" ]
check "zsh keeps the theme prompt" [ "$(in_shell "$h" zsh 'print -r -- $PS1')" = '%n@%m %# ' ]
check "zsh starts without errors" [ ! -s "$h/shell.err" ]
[ -s "$h/shell.err" ] && show "$h/shell.err"

echo "== cancelling"
h=$(new_home)
check "esc on the main menu quits cleanly" run_menu "$h" ESC
check "esc on the profile picker saves nothing" run_menu "$h" "Select profile" ESC Quit
check "  ...and returns to the menu" [ "$(count 'gum choose Select profile' "$SMOKE_LOG")" = 2 ]
check "  ...with no profile saved" [ ! -e "$h/.config/envsetup/profile" ]

echo
if ((failures)); then
	echo "$failures check(s) failed"
	exit 1
fi
echo "all checks passed"
