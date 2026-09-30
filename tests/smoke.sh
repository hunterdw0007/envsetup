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
export SMOKE_LOG=$W/calls.log SMOKE_CHOICES=$W/choices SMOKE_CONFIRMS=$W/confirms
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
: >"$SMOKE_CONFIRMS"

# gum: answers `choose` from $SMOKE_CHOICES (one per line; "ESC", or running out,
# cancels), `confirm` from $SMOKE_CONFIRMS (only "yes" accepts; running out declines),
# fills `input`, and logs every call.
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
	confirm)
		answer=no
		read -r answer <"$SMOKE_CONFIRMS" || true
		sed -i 1d "$SMOKE_CONFIRMS"
		[[ $answer == yes ]] ;;
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
# Options for setup.sh itself go in SETUP_ARGS, answers to gum confirm in CONFIRMS.
SETUP_ARGS=() CONFIRMS=()
run_menu() {
	local home=$1
	shift
	printf '%s\n' "$@" >"$SMOKE_CHOICES"
	printf '%s\n' "${CONFIRMS[@]}" >"$SMOKE_CONFIRMS"
	: >"$SMOKE_LOG"
	HOME=$home PATH="$OFFLINE:$STUBS:$PATH" "$CLONE/setup.sh" "${SETUP_ARGS[@]}" >"$home/setup.out" 2>&1 </dev/tty
}
# Everything under a home (paths + file contents), minus the test's own output files.
snapshot() {
	(
		cd "$1" || exit 1
		find . ! -name setup.out ! -name 'shell.*' | sort
		find . -type f ! -name setup.out ! -name 'shell.*' -exec md5sum {} + | sort
	) | md5sum
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
n_expected() { expected "$1" | wc -l; }
n_installers() {
	local s n=0
	for s in "$CLONE/installers/$1"/*.sh; do [ -f "$s" ] && n=$((n + 1)); done
	echo "$n"
}
# described <count> <text>: the count behind a label must be real, then the menu must show it.
described() { [ "$1" -gt 0 ] && grep -qF -- "$2" "$SMOKE_LOG"; }
# Both run with no gum anywhere on PATH, so they fail if they go anywhere near it.
help_ok() { HOME=$1 PATH=/usr/bin:/bin "$CLONE/setup.sh" --help >"$1/help.out" 2>&1 && grep -q '^Usage: ' "$1/help.out"; }
rejects_unknown() {
	local rc=0
	HOME=$1 PATH=/usr/bin:/bin "$CLONE/setup.sh" --bogus >"$1/bogus.out" 2>&1 || rc=$?
	[ "$rc" = 2 ] && grep -qF 'unknown option: --bogus' "$1/bogus.out"
}
includes() { git config --file "$1/.gitconfig" --get-all include.path || true; }
# PS1 comes from shell/shared/ps1.sh, not the distro's .bashrc.
has_prompt() { [[ "$(in_shell "$1" bash 'printf %s "$PS1"')" == *'$(collapsed_directory)'* ]]; }
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
check "bash loads the aliases" [ "$(in_shell "$h" bash 'alias ll')" = "alias ll='ls -alh'" ]
check "bash gets the prompt" has_prompt "$h"
check "  ...which collapses the path" [ "$(in_shell "$h" bash 'cd /usr/share/doc && collapsed_directory')" = /u/s/doc ]
check "bash gets the functions" [ "$(in_shell "$h" bash 'type -t fetchAll')" = function ]
check "bash gets the work aliases" [ "$(in_shell "$h" bash 'alias kc')" = "alias kc='kubectl'" ]
check "bash starts without errors" [ ! -s "$h/shell.err" ]
[ -s "$h/shell.err" ] && show "$h/shell.err"
check "git gets the shipped defaults" same_list "$(git config --file "$CLONE/git/gitconfig" alias.l)" "$(HOME=$h git config --global --includes alias.l)"
if run_menu "$h" "Run everything" Quit; then pass "re-run exited 0"; else fail "re-run exited non-zero"; fi
check "re-run didn't link twice" [ "$(count '# >>> envsetup >>>' "$h/.bashrc")" = 1 ]
((failures)) && show "$h/setup.out"

echo "== work/lite: Run everything (no sudo: no packages, no installers)"
h=$(new_home)
if run_menu "$h" "Select profile" work lite "Run everything" Quit; then pass "exited 0"; else fail "exited non-zero"; fi
check "linked ~/.bashrc" grep -qF '# >>> envsetup >>>' "$h/.bashrc"
check "no package installs" [ "$(count 'apt-get' "$SMOKE_LOG")" = 0 ]
check "no installers run" [ "$(count 'Running ' "$SMOKE_LOG")" = 0 ]
check "bash loads the aliases" [ "$(in_shell "$h" bash 'alias ll')" = "alias ll='ls -alh'" ]
check "bash skips exports" [ -z "$(in_shell "$h" bash 'printf %s "${EDITOR:-}"')" ]
check "bash skips functions" [ -z "$(in_shell "$h" bash 'type -t fetchAll')" ]
check "bash still gets the prompt" has_prompt "$h"

echo "== home: Run everything (zsh + oh-my-zsh)"
h=$(new_home)
if run_menu "$h" "Select profile" home "Run everything" Quit; then pass "exited 0"; else fail "exited non-zero"; fi
check "installed oh-my-zsh" [ -d "$h/.oh-my-zsh" ]
check "kept the oh-my-zsh .zshrc" grep -qF 'stand-in for the oh-my-zsh theme' "$h/.zshrc"
check "linked ~/.zshrc once" [ "$(count '# >>> envsetup >>>' "$h/.zshrc")" = 1 ]
check "installed common + home packages" same_list "$(expected home)" "$(installed)"
check "zsh loads the aliases" [ "$(in_shell "$h" zsh 'alias ll')" = "ll='ls -alh'" ]
check "zsh keeps the theme prompt" [ "$(in_shell "$h" zsh 'print -r -- $PS1')" = '%n@%m %# ' ]
check "zsh starts without errors" [ ! -s "$h/shell.err" ]
[ -s "$h/shell.err" ] && show "$h/shell.err"

echo "== explaining itself"
h=$(new_home)
check "--help works before gum is installed" help_ok "$h"
check "an unknown option is rejected, not ignored" rejects_unknown "$h"
check "  ...without writing anything" [ ! -e "$h/.config" ]
run_menu "$h" Quit
check "a first run shows a welcome" grep -qF 'Welcome to envsetup' "$SMOKE_LOG"
w=$(n_expected work) wi=$(n_installers work) hm=$(n_expected home)
# Answer with whole lines, the way gum returns a picked label.
run_menu "$h" "Select profile" "work  bash · (as gum returns it)" "lite  no sudo: (as gum returns it)" Quit
check "work is described from its config" described "$w" "work  bash · $w packages · $wi installers ("
check "home is described from its config" described "$hm" "home  zsh + oh-my-zsh · $hm packages · no installers"
check "modes say what needs sudo" described "$w" "full  uses sudo: installs $w packages and runs $wi installers"
check "a picked line is saved as just its name" [ "$(cat "$h/.config/envsetup/profile")/$(cat "$h/.config/envsetup/mode")" = work/lite ]
run_menu "$h" Quit
check "no welcome once a profile is saved" not_grep 'Welcome to envsetup' "$SMOKE_LOG"
h=$(new_home)
mkdir -p "$h/.config/envsetup"
printf 'ENVSETUP_SHELL=bash\nENVSETUP_SKIP=(%s)\n' "$(expected home | head -1)" >"$h/.config/envsetup/config.sh"
run_menu "$h" "Select profile" ESC
check "descriptions follow the user's config.sh" described "$hm" "home  bash · $((hm - 1)) packages"

echo "== --dry-run: home, Run everything"
h=$(new_home)
before=$(snapshot "$h")
SETUP_ARGS=(--dry-run)
if run_menu "$h" "Select profile" home "Run everything" Quit; then pass "exited 0"; else fail "exited non-zero"; fi
SETUP_ARGS=()
check "said it would install oh-my-zsh" grep -qF 'would install oh-my-zsh' "$SMOKE_LOG"
check "said it would link ~/.zshrc" grep -qF "would add a 4-line block to $h/.zshrc" "$SMOKE_LOG"
check "said it would ask for a git identity" grep -qF 'would ask for your git user.name' "$SMOKE_LOG"
check "said it would install common + home packages" described "$hm" "would install $hm packages"
check "ran nothing that changes the machine" not_grep '^\(apt-get\|curl\|chsh\) ' "$SMOKE_LOG"
check "left \$HOME exactly as it was" [ "$(snapshot "$h")" = "$before" ]
touch "$h/.bashrc"
echo "# control" >>"$h/.bashrc"
check "  ...(control: the snapshot does notice a change)" [ "$(snapshot "$h")" != "$before" ]
((failures)) && show "$h/setup.out"

echo "== --dry-run: config edits last only for the session"
h=$(new_home)
before=$(snapshot "$h")
printf '#!/bin/sh\necho ENVSETUP_SHELL=bash >>"$1"\n' >$W/editor
chmod +x $W/editor
export EDITOR=$W/editor
SETUP_ARGS=(--dry-run)
run_menu "$h" "Edit config" "Select profile" ESC Quit || true
SETUP_ARGS=()
unset EDITOR
check "the edit applied within the session" described "$hm" "home  bash · $hm packages"
check "  ...and nothing was saved" [ "$(snapshot "$h")" = "$before" ]

echo "== Preview everything (normal session): work/full"
h=$(new_home)
if run_menu "$h" "Select profile" work full "Preview everything" Quit; then pass "exited 0"; else fail "exited non-zero"; fi
check "said it would install common + work packages" described "$w" "would install $w packages"
check "said it would run the work installers" described "$wi" "would run $wi installer scripts"
check "ran nothing that changes the machine" not_grep '^\(apt-get\|curl\|chsh\) ' "$SMOKE_LOG"
check "left ~/.bashrc as it was" cmp -s /etc/skel/.bashrc "$h/.bashrc"
check "still saved the profile you picked" [ "$(cat "$h/.config/envsetup/profile" 2>/dev/null)" = work ]

echo "== install.sh passes options to setup.sh"
: >"$SMOKE_LOG"
if PATH="$STUBS:$PATH" ENVSETUP_REPO_URL=$SRC ENVSETUP_DIR=$W/clone2 bash "$SRC/install.sh" --help >$W/install2.out 2>&1 </dev/null; then
	pass "install.sh --help exited 0"
else
	fail "install.sh --help exited non-zero"
	show $W/install2.out
fi
check "  ...and printed setup.sh's help" grep -qF -- '--dry-run' $W/install2.out

echo "== --uninstall: work/full"
h=$(new_home)
run_menu "$h" "Select profile" work full "Run everything" Quit
gc=$h/.config/envsetup/gitconfig
check "(before: git includes envsetup's file)" [ "$(includes "$h")" = "$gc" ]
check "(before: a profile is saved)" [ -f "$h/.config/envsetup/profile" ]
SETUP_ARGS=(--uninstall) CONFIRMS=(yes)
if run_menu "$h"; then pass "exited 0"; else fail "exited non-zero"; fi
check ".bashrc is byte-for-byte what it was" cmp -s /etc/skel/.bashrc "$h/.bashrc"
check "removed the git include" [ -z "$(includes "$h")" ]
check "kept the git identity" [ "$(git config --file "$h/.gitconfig" user.name)" = "Smoke Test" ]
check "removed envsetup's saved state" [ ! -e "$h/.config/envsetup" ]
check "bash is back to the distro's aliases" [ "$(in_shell "$h" bash 'alias ll')" = "alias ll='ls -alF'" ]
check "didn't touch the login shell" not_grep '^chsh ' "$SMOKE_LOG"
before=$(snapshot "$h")
check "a second --uninstall exits 0" run_menu "$h"
check "  ...and changes nothing" [ "$(snapshot "$h")" = "$before" ]
SETUP_ARGS=() CONFIRMS=()
((failures)) && show "$h/setup.out"

echo "== --uninstall: declining, and with --dry-run"
h=$(new_home)
run_menu "$h" "Select profile" work full "Run everything" Quit
before=$(snapshot "$h")
SETUP_ARGS=(--uninstall)
check "declining exits 0" run_menu "$h"
check "  ...and changes nothing" [ "$(snapshot "$h")" = "$before" ]
SETUP_ARGS=(--dry-run --uninstall) CONFIRMS=(yes)
check "--dry-run --uninstall exits 0" run_menu "$h"
SETUP_ARGS=() CONFIRMS=()
check "said it would remove the ~/.bashrc block" grep -qF "would remove the envsetup block from $h/.bashrc" "$SMOKE_LOG"
check "said it would remove the git include" grep -qF "would remove the include of $h/.config/envsetup/gitconfig" "$SMOKE_LOG"
check "  ...and changes nothing" [ "$(snapshot "$h")" = "$before" ]

echo "== Uninstall from the menu: home on zsh, with a config.sh"
h=$(new_home)
mkdir -p "$h/.config/envsetup"
echo 'alias smoke=true' >"$h/.config/envsetup/config.sh"
run_menu "$h" "Select profile" home "Run everything" Quit
check "(before: ~/.zshrc is linked)" grep -qF '# >>> envsetup >>>' "$h/.zshrc"
# Remove? yes; keep config.sh? no; keep zsh as login shell? no.
CONFIRMS=(yes no no)
if SHELL=/usr/bin/zsh run_menu "$h" Uninstall; then pass "exited 0"; else fail "exited non-zero"; fi
CONFIRMS=()
check "unlinked ~/.zshrc" not_grep '# >>> envsetup >>>' "$h/.zshrc"
check "  ...keeping the rest of it" grep -qF 'stand-in for the oh-my-zsh theme' "$h/.zshrc"
check "deleted config.sh when told to" [ ! -e "$h/.config/envsetup/config.sh" ]
check "switched the login shell back to bash" grep -q '^chsh -s .*/bash$' "$SMOKE_LOG"
check "said how to remove oh-my-zsh" grep -qF 'uninstall_oh_my_zsh' "$SMOKE_LOG"
check "closed the menu afterwards" [ "$(count 'gum choose' "$SMOKE_LOG")" = 1 ]
h=$(new_home)
mkdir -p "$h/.config/envsetup"
echo 'alias smoke=true' >"$h/.config/envsetup/config.sh"
run_menu "$h" "Select profile" work lite Quit
SETUP_ARGS=(--uninstall) CONFIRMS=(yes yes)
run_menu "$h" || true
SETUP_ARGS=() CONFIRMS=()
check "kept config.sh by default" [ -f "$h/.config/envsetup/config.sh" ]
check "  ...but removed the saved profile" [ ! -e "$h/.config/envsetup/profile" ]

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
