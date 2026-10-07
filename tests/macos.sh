#!/usr/bin/env bash
# Tests envsetup on this Mac without changing it: install.sh, setup.sh and the shells it
# configures run against throwaway $HOMEs, with gum's menu scripted and `brew install`
# (and chsh) recorded instead of run. Other brew commands (shellenv, info) are real, so
# the formulas envsetup asks for are checked against Homebrew itself. The one download
# is oh-my-zsh, into a throwaway $HOME.
#
#   tests/macos.sh            # writes macos-report/<time>/report.md
#
# CI runs it on GitHub's macOS runners when asked (.github/workflows/macos.yml). Tests
# the commit checked out here, so commit first. Runs under macOS's bash 3.2 or
# Homebrew's, so it sticks to bash 3.2 (no readarray, associative arrays, ${x,,}).
# shellcheck disable=SC2016 # single-quoted code is meant to expand in the stubs and test shells
set -uo pipefail # no -e: every check reports its own outcome and the next one runs

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
if [[ "$OSTYPE" != darwin* && -z "${MACOS_TEST_FORCE:-}" ]]; then
	echo "This is the macOS test. On Linux, use tests/smoke.sh or tests/distros/run.sh." >&2
	exit 2
fi
out=${MACOS_TEST_OUT:-$PWD/macos-report/$(date +%Y%m%d-%H%M%S)}
mkdir -p "$out"
T=$(mktemp -d)
[[ -n "${KEEP:-}" ]] || trap 'rm -rf "$T"' EXIT
results=$out/results.tsv
: >"$results"

# result <PASS|FAIL|WARN|SKIP> <check> [detail]
result() {
	printf '%s\t%s\t%s\n' "$1" "$2" "${3:-}" >>"$results"
	printf '  %-4s %s%s\n' "$1" "$2" "${3:+  ($3)}"
}
# check <check> <command...>: PASS if the command succeeds.
check() {
	local name=$1
	shift
	if "$@"; then result PASS "$name"; else result FAIL "$name"; fi
}
has() { grep -qF -- "$1" "$2"; }
hasnt() { ! grep -qF -- "$1" "$2"; }
count() { grep -cF -- "$1" "$2"; }
# Startup noise from shells without a terminal; anything else on stderr is an error.
clean() { ! grep -vE 'job control|terminal process group|pgrp|cannot set terminal|^$' "$1" | grep -q .; }

real_brew=$(command -v brew) || for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
	if [[ -x "$b" ]]; then real_brew=$b && break; fi
done
brew_prefix=${real_brew%/bin/brew}
new_bash=
for b in "$brew_prefix/bin/bash" /opt/homebrew/bin/bash /usr/local/bin/bash; do
	if [[ -x "$b" ]] && "$b" -c '((BASH_VERSINFO[0] >= 4))' 2>/dev/null; then new_bash=$b && break; fi
done

# --- stand-ins ------------------------------------------------------------------------
stubs=$T/stubs
mkdir -p "$stubs"
export MT_LOG=$T/calls.log MT_CHOICES=$T/choices MT_CONFIRMS=$T/confirms REAL_BREW=$real_brew
cat >"$stubs/gum" <<'EOF'
#!/bin/bash
echo "gum $*" >>"$MT_LOG"
pop() { head -n 1 "$1" 2>/dev/null; tail -n +2 "$1" >"$1.tmp" 2>/dev/null; mv "$1.tmp" "$1"; }
case $1 in
choose)
	a=$(pop "$MT_CHOICES")
	if [ -z "$a" ] || [ "$a" = ESC ]; then exit 1; fi
	echo "$a" ;;
confirm) [ "$(pop "$MT_CONFIRMS")" = yes ]; exit ;;
input) case "$*" in *@*) echo mac@example.com ;; *) echo "Mac Tester" ;; esac ;;
style) echo "${@: -1}" ;;
esac
exit 0
EOF
# brew: installs are recorded, everything else (shellenv, info, --prefix) is the real one.
cat >"$stubs/brew" <<'EOF'
#!/bin/bash
case $1 in
install | reinstall | upgrade | tap | uninstall) echo "brew $*" >>"$MT_LOG"; exit 0 ;;
esac
[ -n "$REAL_BREW" ] || exit 1
exec "$REAL_BREW" "$@"
EOF
printf '#!/bin/sh\necho "chsh $*" >>"$MT_LOG"\n' >"$stubs/chsh"
# The real one would open Apple's installer dialog on a Mac without the Command Line
# Tools; whether they're installed is checked on its own, with /usr/bin/xcode-select.
printf '#!/bin/sh\necho /Library/Developer/CommandLineTools\n' >"$stubs/xcode-select"
chmod +x "$stubs"/*
# A newer bash first on PATH, as Homebrew's bin dir would be.
[[ -n "$new_bash" ]] && ln -s "$new_bash" "$stubs/bash"

# new_home <name>: a throwaway $HOME with envsetup cloned into it, as install.sh would.
new_home() {
	local h=$T/home-$1
	mkdir -p "$h"
	git clone -q "$root" "$h/envsetup"
	echo "$h"
}
# menu <home> <login shell> <confirms...> -- <choices...>: runs setup.sh, answering gum.
menu() {
	local h=$1 sh=$2
	shift 2
	: >"$MT_CONFIRMS"
	while (($#)) && [[ $1 != -- ]]; do echo "$1" >>"$MT_CONFIRMS" && shift; done
	shift
	: >"$MT_CHOICES"
	for a in "$@"; do echo "$a" >>"$MT_CHOICES"; done
	: >"$MT_LOG"
	HOME=$h SHELL=$sh PATH="$stubs:$PATH" "$h/envsetup/setup.sh" ${SETUP_ARGS:+"$SETUP_ARGS"} </dev/null >"$h/setup.out" 2>&1
}
# in_shell <home> <shell and flags...> -- <command>: an interactive shell loading that home.
in_shell() {
	local h=$1 cmd
	shift
	local sh=()
	while [[ $1 != -- ]]; do sh+=("$1") && shift; done
	cmd=$2
	HOME=$h PATH="$stubs:$PATH" "${sh[@]}" -c "$cmd" </dev/null 2>"$h/shell.err"
}

{
	echo "macOS $(sw_vers -productVersion 2>/dev/null) ($(uname -m)), commit $(git -C "$root" rev-parse --short HEAD)"
	echo "/bin/bash $(/bin/bash -c 'echo $BASH_VERSION'), zsh $(zsh --version 2>/dev/null | awk '{print $2}'), login shell ${SHELL:-unset}"
	echo "Homebrew: ${real_brew:-none} ($([[ -n "$real_brew" ]] && "$real_brew" --version 2>/dev/null | head -n 1))"
	echo "newer bash: ${new_bash:-none}${new_bash:+ ($("$new_bash" -c 'echo $BASH_VERSION'))}"
	echo "Command Line Tools: $(xcode-select -p 2>/dev/null || echo 'not installed')"
} >"$out/environment.txt"
sed 's/^/  /' "$out/environment.txt"
[[ -n "$(git -C "$root" status --porcelain)" ]] && result WARN "working tree" "uncommitted changes aren't tested; commit first"

clt_installed() { /usr/bin/xcode-select -p >/dev/null 2>&1; }
check "Command Line Tools are installed (install.sh needs them)" clt_installed

echo "== install.sh (from macOS's bash 3.2, cloning this checkout)"
if [[ -z "$real_brew" ]]; then
	# It would stop to ask about installing Homebrew.
	result SKIP "install.sh" "Homebrew isn't installed"
else
	h=$T/home-install
	mkdir -p "$h"
	: >"$MT_LOG"
	# script(1) gives it a terminal: it hands off to setup.sh with stdin from /dev/tty.
	HOME=$h PATH="$stubs:/usr/bin:/bin:/usr/sbin:/sbin" ENVSETUP_REPO_URL=$root ENVSETUP_DIR=$h/envsetup \
		script -q /dev/null /bin/bash "$root/install.sh" --help </dev/null >"$out/install.log" 2>&1
	rc=$?
	handed_off() { ((rc == 0)) && grep -q '^Usage: ' "$out/install.log"; }
	check "install.sh exits 0 and hands off to setup.sh --help" handed_off
	check "  ...after cloning" test -x "$h/envsetup/setup.sh"
	if [[ -n "$new_bash" ]]; then
		check "  ...without reinstalling bash (Homebrew's is 4+)" hasnt "brew install bash" "$MT_LOG"
	else
		check "  ...asking Homebrew for a newer bash" has "brew install bash" "$MT_LOG"
	fi
fi

echo "== setup.sh under macOS's bash 3.2"
h=$(new_home bash32)
HOME=$h /bin/bash "$h/envsetup/setup.sh" --help >"$out/bash32-help.log" 2>&1
check "--help works under /bin/bash" grep -q '^Usage: ' "$out/bash32-help.log"
: >"$MT_CHOICES"
: >"$MT_LOG"
HOME=$h PATH="$stubs:$PATH" /bin/bash "$h/envsetup/setup.sh" --dry-run </dev/null >"$out/bash32-dryrun.log" 2>&1
if [[ -n "$new_bash" ]]; then
	check "re-runs under Homebrew's bash and reaches the menu" has "gum choose" "$MT_LOG"
	check "  ...keeping --dry-run" has "Dry run: nothing is saved" "$MT_LOG"
else
	check "without a newer bash, says how to get one" has "brew install bash" "$out/bash32-dryrun.log"
	result WARN "Homebrew's bash" "not installed (brew install bash); the checks below need it and are skipped"
fi

if [[ -n "$new_bash" ]]; then
	echo "== work/full, zsh login shell: Run everything"
	hz=$(new_home zsh)
	menu "$hz" /bin/zsh -- "Select profile" work full "Run everything" Quit
	rc=$?
	cp "$MT_LOG" "$out/work-full.calls"
	cp "$hz/setup.out" "$out/work-full.log"
	check "exited 0" test "$rc" = 0
	check "linked ~/.bashrc once" test "$(count '# >>> envsetup >>>' "$hz/.bashrc")" = 1
	check "linked ~/.zshrc once (the login shell's)" test "$(count '# >>> envsetup >>>' "$hz/.zshrc")" = 1
	check "packages go through Homebrew" grep -q '^brew install ' "$out/work-full.calls"
	check "  ...dig as Homebrew's bind" has "brew install bind" "$out/work-full.calls"
	for p in strace iotop sysstat net-tools tar dnsutils; do
		check "  ...nothing asked of Homebrew for $p" hasnt "brew install $p" "$out/work-full.calls"
	done
	check "git config included from the throwaway ~/.gitconfig" grep -q 'envsetup/gitconfig' "$hz/.gitconfig"

	echo "== work/lite, bash login shell: Run everything"
	hb=$(new_home bash)
	menu "$hb" /bin/bash -- "Select profile" work lite "Run everything" Quit
	rc=$?
	cp "$hb/setup.out" "$out/work-lite.log"
	check "exited 0" test "$rc" = 0
	check "linked ~/.bash_profile (what macOS's login bash reads)" test "$(count '# >>> envsetup >>>' "$hb/.bash_profile")" = 1
	check "installed nothing" hasnt "brew install" "$MT_LOG"

	echo "== home: Set up zsh + oh-my-zsh, then Run everything"
	hh=$(new_home home)
	menu "$hh" /bin/bash yes -- "Select profile" home "Set up zsh + oh-my-zsh" "Run everything" Quit
	rc=$?
	cp "$MT_LOG" "$out/home.calls"
	cp "$hh/setup.out" "$out/home.log"
	check "exited 0" test "$rc" = 0
	check "installed oh-my-zsh (real download)" test -d "$hh/.oh-my-zsh"
	check "linked ~/.zshrc once" test "$(count '# >>> envsetup >>>' "$hh/.zshrc")" = 1
	check "switched the login shell with chsh (recorded)" grep -q '^chsh -s .*zsh' "$out/home.calls"
	check "  ...and noted it for uninstall" test -f "$hh/.config/envsetup/chsh"

	echo "== installers: Homebrew instead of Linux downloads"
	hi=$(new_home installers)
	printf '#!/bin/sh\necho "curl $*" >>"$MT_LOG"\nexit 1\n' >"$T/curl"
	chmod +x "$T/curl"
	brewed() { has "brew install $1" "$MT_LOG" && hasnt 'curl ' "$MT_LOG"; }
	for pair in work/kubectl:kubernetes-cli work/helm:helm work/gh:gh work/awscli:awscli \
		work/terraform:hashicorp/tap/terraform extras/starship:starship extras/lazygit:lazygit \
		extras/k9s:k9s extras/yq:yq extras/mise:mise extras/uv:uv; do
		script=${pair%%:*} formula=${pair#*:}
		: >"$MT_LOG"
		# Only system dirs on PATH, so tools you already have don't turn this into a no-op.
		ENVSETUP_ROOT=$hi/envsetup PATH="$stubs:$T:/usr/bin:/bin:/usr/sbin:/sbin" \
			bash "$hi/envsetup/installers/$script.sh" >"$out/installer-${script##*/}.log" 2>&1
		check "${script##*/}: brew install $formula, no download" brewed "$formula"
	done
	ENVSETUP_ROOT=$hi/envsetup PATH="$stubs:/usr/bin:/bin:/usr/sbin:/sbin" bash "$hi/envsetup/installers/home/docker.sh" >"$out/installer-docker.log" 2>&1
	check "docker: points at Docker Desktop" has "Docker Desktop" "$out/installer-docker.log"

	echo "== the shells it configures"
	check "zsh: loads the aliases" test "$(in_shell "$hz" zsh -i -- 'alias ll')" = "ll='ls -alh'"
	check "  ...with ls in BSD color (ls -G)" test "$(in_shell "$hz" zsh -i -- 'alias ls')" = "ls='ls -G'"
	check "  ...which works" test "$(in_shell "$hz" zsh -i -- 'ls >/dev/null && echo ok')" = ok
	check "  ...and starts without errors" clean "$hz/shell.err"
	cp "$hz/shell.err" "$out/zsh.err"
	check "zsh with oh-my-zsh: loads the aliases" test "$(in_shell "$hh" zsh -i -- 'alias ll')" = "ll='ls -alh'"
	check "  ...without errors" clean "$hh/shell.err"
	cp "$hh/shell.err" "$out/zsh-omz.err"
	check "/bin/bash login shell: loads the aliases" test "$(in_shell "$hb" /bin/bash -l -i -- 'alias ll')" = "alias ll='ls -alh'"
	prompt_set() { [[ $(in_shell "$hb" /bin/bash -l -i -- 'printf %s "$PS1"') == *collapsed_directory* ]]; }
	check "  ...and the prompt" prompt_set
	check "  ...and, in lite, none of the functions" test "$(in_shell "$hb" /bin/bash -l -i -- 'type -t branchAll || echo none')" = none
	check "  ...without errors" clean "$hb/shell.err"
	cp "$hb/shell.err" "$out/bash32.err"
	# The home profile (full mode) linked ~/.bash_profile too: its login shell was still bash.
	needs_bash4() { [[ $(in_shell "$hh" /bin/bash -l -i -- 'branchAll 2>&1; echo "rc=$?"') == *"needs bash 4"*rc=1 ]]; }
	check "/bin/bash login shell, full mode: the functions say they need bash 4" needs_bash4
	check "Homebrew's bash: gets the functions" test "$(in_shell "$hz" "$new_bash" -i -- 'type -t branchAll')" = function
	# Two repos, one a commit ahead of its remote, for the prompt and branchAll.
	r=$T/repos
	mkdir -p "$r"
	git init -q --bare "$T/remote.git"
	git clone -q "$T/remote.git" "$r/one" 2>/dev/null
	(cd "$r/one" && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m one && git push -q origin HEAD 2>/dev/null &&
		git -c user.email=t@t -c user.name=t commit -q --allow-empty -m two)
	git clone -q "$T/remote.git" "$r/two" 2>/dev/null
	export MT_REPOS=$r
	ba=$(in_shell "$hz" "$new_bash" -i -- 'cd "$MT_REPOS" && branchAll')
	echo "$ba" >"$out/branchAll.txt"
	table() { [[ $ba == *Repository* && $ba == *one* && $ba == *two* ]]; }
	check "  ...branchAll prints its table with BSD column" table
	check "  ...without column errors" hasnt "illegal option" "$hz/shell.err"
	ahead() { [[ $(in_shell "$hz" "$new_bash" -i -- 'cd "$MT_REPOS/one" && parse_git_tracking') == *'⤻ 1'* ]]; }
	check "  ...prompt shows a commit ahead" ahead
	if command -v bat >/dev/null || command -v batcat >/dev/null; then
		manpager() { [[ $(in_shell "$hz" "$new_bash" -i -- 'printf %s "$MANPAGER"') == *'col -bx'* ]]; }
		check "MANPAGER strips overstrikes with col" manpager
	else
		result SKIP "MANPAGER" "bat isn't installed"
	fi
	if [[ -n "$real_brew" ]]; then
		# A zsh whose PATH has none of Homebrew's dirs.
		bare_zsh() { HOME=$hz PATH=/usr/bin:/bin zsh -i -c "$1" 2>/dev/null; }
		finds_brew() { [[ -n $(bare_zsh 'command -v brew') ]]; }
		check "a shell without Homebrew on PATH still finds brew" finds_brew
		if [[ -x "$brew_prefix/bin/bat" ]]; then
			cat_is_bat() { [[ $(bare_zsh 'alias cat') == *bat* ]]; }
			check "  ...and its bat, for the cat alias" cat_is_bat
		else
			result SKIP "cat alias without Homebrew on PATH" "Homebrew's bat isn't installed"
		fi
	fi
	for pair in direnv:_direnv_hook zoxide:__zoxide_z mise:_mise_hook; do
		t=${pair%%:*} fn=${pair#*:}
		if command -v "$t" >/dev/null; then
			check "zsh hooks $t" test "$(in_shell "$hz" zsh -i -- "typeset -f $fn >/dev/null && echo hooked")" = hooked
		else
			result SKIP "$t hook" "$t isn't installed"
		fi
	done
	if command -v fzf >/dev/null; then
		# Key bindings need a terminal; script(1) gives the shell one.
		fzf_bound() { HOME=$hz PATH="$stubs:$PATH" script -q /dev/null zsh -i -c 'bindkey "^R"' </dev/null 2>/dev/null | grep -q fzf; }
		check "zsh binds fzf to Ctrl-R" fzf_bound
	else
		result SKIP "fzf key bindings" "fzf isn't installed"
	fi

	echo "== uninstall"
	SETUP_ARGS=--uninstall menu "$hz" /bin/zsh yes --
	check "zsh login shell envsetup didn't set: exits 0" test $? = 0
	unlinked() { hasnt '# >>> envsetup >>>' "$hz/.bashrc" && hasnt '# >>> envsetup >>>' "$hz/.zshrc"; }
	check "  ...unlinks ~/.bashrc and ~/.zshrc" unlinked
	check "  ...without offering to change the login shell" hasnt "Keep zsh as your login shell" "$MT_LOG"
	SETUP_ARGS=--uninstall menu "$hh" /bin/zsh yes no --
	cp "$MT_LOG" "$out/uninstall-home.calls"
	cp "$hh/setup.out" "$out/uninstall-home.log"
	check "login shell envsetup switched: offers to switch back" has "Keep zsh as your login shell" "$MT_LOG"
	check "  ...and does (chsh recorded)" grep -q '^chsh -s .*bash' "$MT_LOG"
	SETUP_ARGS=--uninstall menu "$hb" /bin/bash yes --
	check "bash login shell: unlinks ~/.bash_profile" hasnt '# >>> envsetup >>>' "$hb/.bash_profile"
fi

echo "== Homebrew has every formula envsetup asks for"
if [[ -z "$real_brew" ]]; then
	result SKIP "formulas" "Homebrew isn't installed"
elif [[ -z "$new_bash" ]]; then
	result SKIP "formulas" "needs Homebrew's bash to read packages/names.txt"
else
	formulas=$(ENVSETUP_ROOT=$root "$new_bash" -c 'source "$ENVSETUP_ROOT/lib/common.sh"
		for p in $(grep -hvE "^[[:space:]]*(#|$)" "$ENVSETUP_ROOT"/packages/{common,home,work}.txt) chsh; do envsetup::pkg_name brew "$p"; done' | sort -u)
	for f in $formulas kubernetes-cli helm gh awscli starship lazygit k9s yq mise uv bash zsh gum; do
		if "$real_brew" info --formula "$f" >/dev/null 2>&1; then result PASS "brew info $f"; else result FAIL "brew info $f" "no such formula"; fi
	done
	if "$real_brew" tap 2>/dev/null | grep -qx hashicorp/tap; then
		check "brew info hashicorp/tap/terraform" "$real_brew" info --formula hashicorp/tap/terraform
	else
		result SKIP "hashicorp/tap/terraform" "tap not added yet; brew install adds it"
	fi
fi

# --- report ---------------------------------------------------------------------------
{
	echo "# envsetup on macOS"
	echo
	sed 's/^/    /' "$out/environment.txt"
	echo
	printf '%s passed, %s failed, %s warnings, %s skipped. Logs are next to this file.\n' \
		"$(grep -c '^PASS' "$results")" "$(grep -c '^FAIL' "$results")" "$(grep -c '^WARN' "$results")" "$(grep -c '^SKIP' "$results")"
	echo
	echo "## Problems"
	echo
	grep -vE '^(PASS|SKIP)' "$results" | while IFS=$'\t' read -r status name detail; do
		echo "- **$status** $name${detail:+: $detail}"
	done
	grep -qvE '^(PASS|SKIP)' "$results" || echo "None."
	echo
	echo "## Skipped"
	echo
	grep '^SKIP' "$results" | while IFS=$'\t' read -r _ name detail; do echo "- $name: $detail"; done
	grep -q '^SKIP' "$results" || echo "None."
	echo
	echo "## All checks"
	echo
	while IFS=$'\t' read -r status name detail; do echo "- $status $name${detail:+ ($detail)}"; done <"$results"
} >"$out/report.md"
echo
echo "Report: $out/report.md"
! grep -q '^FAIL' "$results"
