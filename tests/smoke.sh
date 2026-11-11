#!/usr/bin/env bash
# The smoke test runs envsetup for real on a bare Ubuntu container.
# Only the slow parts and the network parts are fakes: gum's menus, package installs and vendor downloads.
# These parts are real: the git install, the clone and the setup.sh menu flow.
# The startup file links, and a real bash and zsh that load the result, are real too.
#
#   docker run --rm -t -v "$PWD:/src:ro" ubuntu:24.04 bash /src/tests/smoke.sh
#
# The test needs a terminal (-t), because install.sh starts setup.sh through /dev/tty.
# It needs a temporary container, because it installs git and zsh and writes to /root.
# SMOKE_APT_CACHE is a folder of apt lists and .debs for git, zsh and jq (lists/, archives/).
# With it, the test can run offline, as CI does (see the smoke job in ci.yml).
# From CI, Ubuntu's package servers often take minutes.
# shellcheck disable=SC2016 # code in single quotes expands later, in the fakes and test shells
set -euo pipefail

SRC=/src
CLONE=/root/envsetup
W=/tmp/smoke
STUBS=$W/stubs     # fake gum and sudo, on PATH for every run
OFFLINE=$W/offline # fake package manager, curl, chsh, and vendor tools that count as installed
HOOKS=$W/hooks     # fake direnv and zoxide that print a marker function as their hook
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
none_exist() { for f; do [ ! -e "$f" ] || return 1; done; }
# none_exist_in <text> <file>... passes when none of the files contain the text.
none_exist_in() {
	local text=$1 f
	shift
	for f; do ! grep -qF -- "$text" "$f" || return 1; done
}
not() { ! "$@"; }
same_list() { [ -n "$1" ] && [ "$1" = "$2" ]; } # an empty expected list means a broken test, not a pass
# Both commits must exist, so two failed lookups cannot count as equal.
same_commit() {
	local a b
	a=$(git -C "$1" rev-parse --verify -q HEAD) && b=$(git -C "$2" rev-parse --verify -q HEAD) && [ "$a" = "$b" ]
}

# Find the commit under test, for install.sh's ENVSETUP_VERSION.
# Without it, install.sh would pick the newest release.
# Use the branch that /src has checked out.
# When HEAD is detached, as in CI, use the commit itself.
# Read the files by hand, because git is missing until the test installs it.
read -r UNDER_TEST <"$SRC/.git/HEAD"
UNDER_TEST=${UNDER_TEST#ref: refs/heads/}

{ : </dev/tty; } 2>/dev/null || {
	echo "No TTY: run the container with -t (see the header of this file)." >&2
	exit 2
}
if [[ -n "${SMOKE_APT_CACHE:-}" ]]; then
	rm -f /etc/apt/apt.conf.d/docker-clean # it deletes the .debs after apt installs them
	cp -a "$SMOKE_APT_CACHE/lists/." /var/lib/apt/lists/
	cp "$SMOKE_APT_CACHE"/archives/*.deb /var/cache/apt/archives/
	# Offline, apt-get update would spend about 8 seconds on retries.
	# One failed try for each source is enough.
	echo 'Acquire::Retries "0";' >/etc/apt/apt.conf.d/99smoke
fi
# The container is temporary, so dpkg does not need to fsync every file it unpacks.
# Skip recommended packages, which are half of git's 50 or so packages.
# The container is then smaller and faster.
echo force-unsafe-io >/etc/dpkg/dpkg.cfg.d/smoke
echo 'APT::Install-Recommends "0";' >/etc/apt/apt.conf.d/98smoke

mkdir -p "$STUBS" "$OFFLINE"
: >"$SMOKE_CONFIRMS"

cp "$SRC/tests/gum.sh" "$STUBS/gum"
# The test is root in the container, and a real machine has sudo.
printf '#!/bin/sh\nexec "$@"\n' >"$STUBS/sudo"

# The fake apt-get refuses any install that includes smoke-conflict, like a real package conflict.
printf '#!/bin/sh\necho "apt-get $*" >>"$SMOKE_LOG"\ncase "$*" in *smoke-conflict*) exit 100 ;; esac\n' >"$OFFLINE/apt-get"
printf '#!/bin/sh\necho "chsh $*" >>"$SMOKE_LOG"\n' >"$OFFLINE/chsh"
# --status asks dpkg-query about each package, and the fake apt-get installs none.
# So the fake dpkg-query reports every package as installed.
printf '#!/bin/sh\necho "install ok installed"\n' >"$OFFLINE/dpkg-query"
# The fake curl serves a fake oh-my-zsh installer, a fake kubectl, and install.sh for the envsetup command.
# Any other download is a bug in the test.
# SMOKE_CURL_FAIL=1 makes every download fail, as offline.
cat >"$OFFLINE/curl" <<'EOF'
#!/bin/sh
echo "curl $*" >>"$SMOKE_LOG"
[ -z "$SMOKE_CURL_FAIL" ] || exit 6
case "$*" in
	*ohmyzsh*) cat <<'OMZ' ;;
mkdir -p "$HOME/.oh-my-zsh"
[ -f "$HOME/.zshrc" ] || echo 'PROMPT="%n@%m %# "  # stand-in for the oh-my-zsh theme' >"$HOME/.zshrc"
OMZ
	*dl.k8s.io*)
		while [ "$1" != -o ]; do shift; done
		printf '#!/bin/sh\necho smoke-kubectl\n' >"$2"
		;;
	*/hunterdw0007/envsetup/main/install.sh) cat /src/install.sh ;;
	*) echo "smoke: unexpected download: curl $*" >&2; exit 1 ;;
esac
EOF
for tool in kubectl helm terraform aws docker lazygit; do printf '#!/bin/sh\n' >"$OFFLINE/$tool"; done
printf '#!/bin/sh\necho "gh $*" >>"$SMOKE_LOG"\n' >"$OFFLINE/gh"
# The container has no openssh-client.
# A real ssh-keygen would also wait for a passphrase.
cp "$SRC/tests/ssh-keygen.sh" "$OFFLINE/ssh-keygen"
mkdir -p "$HOOKS"
printf '#!/bin/sh\necho "_direnv_hook() { :; }"\n' >"$HOOKS/direnv"
printf '#!/bin/sh\necho "__zoxide_z() { :; }"\n' >"$HOOKS/zoxide"
chmod +x "$STUBS"/* "$OFFLINE"/* "$HOOKS"/*

# run_menu <home> <answers...> runs the cloned setup.sh offline and answers the menu.
# Options for setup.sh go in SETUP_ARGS.
# Answers to gum confirm go in CONFIRMS.
# SETUP=curl_bash runs setup.sh through install.sh instead, as `curl ... | bash` does.
SETUP_ARGS=() CONFIRMS=()
run_menu() {
	local home=$1
	shift
	printf '%s\n' "$@" >"$SMOKE_CHOICES"
	printf '%s\n' "${CONFIRMS[@]}" >"$SMOKE_CONFIRMS"
	: >"$SMOKE_LOG"
	HOME=$home PATH="$OFFLINE:$STUBS:$PATH" "${SETUP:-$CLONE/setup.sh}" "${SETUP_ARGS[@]}" >"$home/setup.out" 2>&1 </dev/tty
}
# install.sh downloads into TMP (mktemp -d).
# TMP must be empty after install.sh ends.
TMP=$W/tmp
mkdir -p "$TMP"
# shellcheck disable=SC2120 # run_menu passes it SETUP_ARGS
curl_bash() { ENVSETUP_VERSION=$UNDER_TEST ENVSETUP_REPO_URL=$SRC TMPDIR=$TMP bash "$SRC/install.sh" "$@"; }
left_nothing() { [ -z "$(ls -A "$TMP")" ]; }
# envsetup_in <bash|zsh> <args> runs the envsetup command in a real interactive shell.
# Unlike in_shell, the shell keeps the terminal, because install.sh reads from /dev/tty.
# config.sh sets ENVSETUP_REPO_URL, so the test does not set it here.
# An empty ENVSETUP_VERSION stays empty, so envsetup picks the release itself.
envsetup_in() {
	local sh=$1
	shift
	ENVSETUP_VERSION=${ENVSETUP_VERSION-$UNDER_TEST} TMPDIR=$TMP "$sh" -ic 'envsetup "$@"' envsetup "$@"
}
envsetup_bash() { envsetup_in bash "$@"; }
envsetup_zsh() { envsetup_in zsh "$@"; }
# This prints everything under a home: paths and file contents.
# It leaves out the test's own output files.
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
# described <count> <text> passes when the count behind a label is real and the menu shows the text.
described() { [ "$1" -gt 0 ] && grep -qF -- "$2" "$SMOKE_LOG"; }
# Both checks run without gum on PATH, so they fail if they call gum.
help_ok() { HOME=$1 PATH=/usr/bin:/bin "$CLONE/setup.sh" --help >"$1/help.out" 2>&1 && grep -q '^Usage: ' "$1/help.out"; }
rejects_unknown() {
	local rc=0
	HOME=$1 PATH=/usr/bin:/bin "$CLONE/setup.sh" --bogus >"$1/bogus.out" 2>&1 || rc=$?
	[ "$rc" = 2 ] && grep -qF 'unknown option: --bogus' "$1/bogus.out"
}
includes() { git config --file "$1/.gitconfig" --get-all include.path || true; }
# PS1 comes from shell/shared/ps1.sh, not the distro's .bashrc.
has_prompt() { [[ "$(in_shell "$1" bash 'printf %s "$PROMPT_COMMAND $PS1"')" == *_envsetup_prompt*'${_envsetup_prompt_dir}'* ]]; }
# prompt_var <home> <dir> <var> prints the value that _envsetup_prompt (PROMPT_COMMAND) gives <var> in <dir>.
prompt_var() { in_shell "$1" bash "cd '$2' && _envsetup_prompt && printf %s \"\$_envsetup_prompt_$3\""; }
# in_shell <home> <bash|zsh> <cmd> runs cmd in a real interactive shell that loads the linked startup file.
# stderr goes to <home>/shell.err.
# The function drops the job control notices that a shell without a terminal prints.
in_shell() {
	local out
	out=$(HOME=$1 setsid "$2" -i -c "$3" 2>"$1/shell.raw" </dev/null)
	grep -vE 'job control|terminal process group|pgrp' "$1/shell.raw" >"$1/shell.err" || true
	echo "$out"
}

# not_interactive <home> <cmd> runs cmd in a non-interactive bash that still runs envsetup's block.
# `ssh host cmd` does this where ~/.bashrc does not return early, as on Fedora.
# Ubuntu's ~/.bashrc returns early.
# So the function copies the block out and runs it through BASH_ENV.
# The output includes stderr.
not_interactive() {
	sed -n '/^# >>> envsetup >>>$/,/^# <<< envsetup <<<$/p' "$1/.bashrc" >"$1/rc-block.sh"
	HOME=$1 BASH_ENV=$1/rc-block.sh bash -c "$2" 2>&1 </dev/null
}

echo "== install.sh on macOS: stops before it changes anything (#103)"
# bash keeps an OSTYPE from the environment.
# This scenario runs first, while the container still has no git.
mac() { OSTYPE=darwin24 curl_bash >$W/mac.out 2>&1; }
check "exited non-zero" not mac
check "  ...named the last release for macOS" grep -qF 'ENVSETUP_VERSION=v0.3.0 bash' $W/mac.out
check "  ...installed no git" not has git
check "  ...and downloaded nothing" left_nothing

echo "== install.sh without git: shows the command that installs git, then stops (#104)"
# The test runs as root, so the commands have no sudo.
no_git() { curl_bash >$W/no-git.out 2>&1; }
check "exited non-zero" not no_git
check "  ...named apt-get" grep -qF 'This machine has apt-get.' $W/no-git.out
check "  ...showed the command" grep -qxF '  apt-get update && apt-get install git' $W/no-git.out
check "  ...said to run the curl command again" grep -qF 'run the curl command again' $W/no-git.out
check "  ...installed no git" not has git
check "  ...and downloaded nothing" left_nothing
# Each folder on PATH holds one fake package manager and nothing else.
# So install.sh finds only that package manager.
only_pm() { PATH=$W/pm/$1 "$BASH" "$SRC/install.sh" >"$W/no-git-$1.out" 2>&1; }
fake() { # fake <dir> <command>... adds empty commands to a folder
	local dir=$1
	shift
	mkdir -p "$dir"
	for c; do printf '#!/bin/sh\n' >"$dir/$c"; done
	chmod +x "$dir"/*
}
for want in 'apt-get update && apt-get install git' 'dnf install git' 'zypper install git' 'pacman -Syu git' \
	'apk add git' "nix-env -f '<nixpkgs>' -iA git"; do
	pm=${want%% *}
	fake "$W/pm/$pm" "$pm"
	check "only $pm: exited non-zero" not only_pm "$pm"
	check "  ...and showed '$want'" grep -qxF "  $want" "$W/no-git-$pm.out"
done
mkdir -p "$W/pm/none"
check "no package manager: exited non-zero" not only_pm none
check "  ...and linked to git's download page" grep -qF 'https://git-scm.com/downloads' "$W/no-git-none.out"
# A user who is not root gets sudo or doas in front of the command.
# Without either one, the hint says to run the command as root.
as_user() { setpriv --reuid=65534 --regid=65534 --clear-groups env PATH="$W/pm/$1" "$BASH" "$SRC/install.sh" >"$W/no-git-$1.out" 2>&1; }
fake "$W/pm/sudo" apt-get sudo
fake "$W/pm/doas" apt-get doas
check "not root, with sudo: exited non-zero" not as_user sudo
check "  ...and showed sudo" grep -qxF '  sudo apt-get update && sudo apt-get install git' "$W/no-git-sudo.out"
check "not root, with doas only: exited non-zero" not as_user doas
check "  ...and showed doas" grep -qxF '  doas apt-get update && doas apt-get install git' "$W/no-git-doas.out"
check "not root, with neither: exited non-zero" not as_user apt-get
check "  ...and said to run it as root" grep -qF 'This machine has apt-get. As root, run:' "$W/no-git-apt-get.out"
check "  ...without a prefix" grep -qxF '  apt-get update && apt-get install git' "$W/no-git-apt-get.out"

echo "== install.sh on a bare box with git: a real download, hand-off to setup.sh"
# The user runs the command from the hint, with real apt.
# yes answers apt-get's question.
hint=$(sed -n 's/^  \(.*git\)$/\1/p' $W/no-git.out)
mkdir -p "$W/apt"
if [[ -n "${SMOKE_APT_CACHE:-}" ]]; then
	# Offline, the cached lists stand in for apt-get update.
	printf '#!/bin/sh\n[ "$1" = update ] && exit 0\nexec /usr/bin/apt-get "$@"\n' >"$W/apt/apt-get"
	chmod +x "$W/apt/apt-get"
fi
# yes reads from a process substitution, so its SIGPIPE does not fail a pipeline under pipefail.
PATH="$W/apt:$PATH" DEBIAN_FRONTEND=noninteractive bash -c "$hint" < <(yes) >$W/git.out 2>&1 || {
	show $W/git.out
	exit 1
}
check "the command from the hint installed git" has git
printf '[safe]\n\tdirectory = *\n' >/etc/gitconfig # /src is owned by the host's user
printf 'Quit\n' >"$SMOKE_CHOICES"
: >"$SMOKE_LOG"
if PATH="$STUBS:$PATH" curl_bash >$W/install.out 2>&1; then
	pass "install.sh exited 0"
else
	fail "install.sh exited non-zero"
	show $W/install.out
fi
check "setup.sh reached the menu on a first run" grep -q '^gum choose Select profile (current: none)' "$SMOKE_LOG"
check "  ...from a download in TMPDIR" grep -qF "to $TMP/" $W/install.out
check "  ...which is gone" left_nothing
# This is a contributor's checkout.
# Most scenarios below run setup.sh from it.
git clone -q "$SRC" "$CLONE"
git -C "$CLONE" checkout -q --detach "$(git -C "$SRC" rev-parse HEAD)"
check "(the checkout is at the commit under test)" same_commit "$SRC" "$CLONE"
mac_setup() { OSTYPE=darwin24 "$CLONE/setup.sh" --help >$W/mac-setup.out 2>&1; }
check "setup.sh in a clone on macOS: exited non-zero" not mac_setup
check "  ...and named the last release for macOS" grep -qF 'git checkout v0.3.0 && ./setup.sh --uninstall' $W/mac-setup.out

# Install a real zsh, so the test checks the shell config in a real zsh.
# Install a real jq, because "Move dotfiles to XDG dirs" reads xdg-ninja's notes with it.
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq zsh jq >$W/zsh.out 2>&1 || {
	show $W/zsh.out
	exit 1
}

echo "== curl | bash, Run everything: only the shell config stays (#86)"
h=$(new_home)
data=$h/.local/share/envsetup
mkdir -p "$h/.config/envsetup"
echo 'ENVSETUP_SHELL=zsh' >"$h/.config/envsetup/config.sh"
SETUP=curl_bash check "exited 0" run_menu "$h" "Select profile" home "Run everything" Quit
check "deleted its download" left_nothing
check "  ...and left no other copy of envsetup" [ -z "$(find "$h" -name setup.sh)" ]
check "copied shell/ for new shells" [ -f "$data/shell/init.sh" ]
check "  ...and recorded the release" same_list "$(PATH=/usr/bin:/bin "$CLONE/setup.sh" --version)" "$(cat "$data/version" 2>/dev/null)"
check "bash loads the aliases" [ "$(in_shell "$h" bash 'alias ll')" = "alias ll='ls -alh'" ]
check "  ...and the prompt" has_prompt "$h"
check "  ...from the copy" [ "$(in_shell "$h" bash 'printf %s "$ENVSETUP_ROOT"')" = "$data" ]
check "  ...without errors" [ ! -s "$h/shell.err" ]
check "zsh loads the aliases" [ "$(in_shell "$h" zsh 'alias ll')" = "ll='ls -alh'" ]
check "  ...without errors" [ ! -s "$h/shell.err" ]
for sh in bash zsh; do
	check "$sh: envsetup version shows the recorded release" same_list "$(cat "$data/version" 2>/dev/null)" "$(in_shell "$h" $sh 'envsetup version')"
	check "  ...envsetup --help lists the commands" grep -q '^  uninstall ' <(in_shell "$h" $sh 'envsetup --help')
	check "  ...envsetup config opens config.sh in \$EDITOR" [ "$(in_shell "$h" $sh 'EDITOR="echo --wait" envsetup config')" = "--wait $h/.config/envsetup/config.sh" ]
	check "  ...a failed download returns 1" [ "$(PATH="$OFFLINE:$PATH" SMOKE_CURL_FAIL=1 in_shell "$h" $sh 'envsetup --dry-run; echo $?')" = 1 ]
	check "  ...and says so" grep -qF 'envsetup: could not download' "$h/shell.err"
	check "  ...an unknown command fails" [ "$(in_shell "$h" $sh 'envsetup bogus; echo $?')" = 2 ]
done
# config.sh sets ENVSETUP_REPO_URL without export, as a user would.
echo "ENVSETUP_REPO_URL=$SRC" >>"$h/.config/envsetup/config.sh"
before=$(snapshot "$h")
for sh in bash zsh; do
	SETUP_ARGS=(--dry-run)
	SETUP=envsetup_$sh check "$sh: envsetup --dry-run in a new shell: exited 0" run_menu "$h" "Run everything" Quit
	SETUP_ARGS=()
	check "  ...ran install.sh from the README's URL" grep -qF 'curl -fsSL https://raw.githubusercontent.com/hunterdw0007/envsetup/main/install.sh' "$SMOKE_LOG"
	check "  ...said it would copy shell/" grep -qF "would copy shell/" "$SMOKE_LOG"
	check "  ...changed nothing" [ "$(snapshot "$h")" = "$before" ]
	check "  ...and deleted its download" left_nothing
done
# Without ENVSETUP_VERSION, envsetup status checks the release in the version file.
SETUP_ARGS=(status)
ENVSETUP_VERSION='' SETUP=envsetup_bash check "envsetup status in a new shell: exited 0" run_menu "$h"
check "  ...downloaded the release that the shells use" grep -qF "Downloaded envsetup $(cat "$data/version" 2>/dev/null) " "$h/setup.out"
check "  ...and ran setup.sh --status" grep -q '^ok .*has the envsetup block' "$h/setup.out"
mv "$OFFLINE/docker" $W/docker
ENVSETUP_VERSION='' SETUP=envsetup_bash check "  ...without docker: exited 1, as setup.sh --status does" not run_menu "$h"
mv $W/docker "$OFFLINE/docker"
SETUP_ARGS=()
check "  ...and named docker" grep -qF 'missing  docker is not on PATH' "$h/setup.out"
check "  ...changed nothing" [ "$(snapshot "$h")" = "$before" ]
check "  ...and deleted its download" left_nothing
SETUP=curl_bash check "the same release again: exited 0" run_menu "$h" "Run everything" Quit
check "  ...and changed nothing" [ "$(snapshot "$h")" = "$before" ]
SETUP_ARGS=(--dry-run)
SETUP=curl_bash check "--dry-run: exited 0" run_menu "$h" "Run everything" Quit
SETUP_ARGS=()
check "  ...said it would copy shell/" grep -qF "would copy shell/" "$SMOKE_LOG"
check "  ...changed nothing" [ "$(snapshot "$h")" = "$before" ]
check "  ...and deleted its download" left_nothing
SETUP_ARGS=(--bogus)
SETUP=curl_bash check "setup.sh failing fails install.sh" not run_menu "$h"
SETUP_ARGS=()
check "  ...which still deletes its download" left_nothing
# Ctrl-C sends a signal to the terminal's foreground job: gum, setup.sh and install.sh.
# Job control (set -m) gives install.sh its own process group, as a terminal would.
signalled() {
	set -m
	SETUP=curl_bash run_menu "$h" "$1"
	local rc=$?
	set +m
	[ "$rc" -ge 128 ]
}
check "Ctrl-C ends install.sh" signalled SIGINT
check "  ...which still deletes its download" left_nothing
check "so does a kill" signalled SIGTERM
check "  ...which still deletes its download" left_nothing
# The answers: remove, yes; keep config.sh, no.
SETUP_ARGS=(uninstall) CONFIRMS=(yes no)
SETUP=envsetup_bash check "envsetup uninstall (curl | bash -s -- --uninstall): exited 0" run_menu "$h"
SETUP_ARGS=() CONFIRMS=()
check "  ...removed the copy of shell/" [ ! -e "$data" ]
check "  ...the rc blocks" none_exist_in '# >>> envsetup >>>' "$h/.bashrc" "$h/.zshrc"
check "  ...and the state, config.sh too when told to" [ ! -e "$h/.config/envsetup" ]
check "  ...and deleted its download" left_nothing
((failures)) && show "$h/setup.out"

echo "== work/full: Run everything"
h=$(new_home)
check "exited 0" run_menu "$h" "Select profile" work full "Run everything" Quit
check "linked ~/.bashrc once" [ "$(count '# >>> envsetup >>>' "$h/.bashrc")" = 1 ]
check "installed common + work packages" same_list "$(expected work)" "$(installed)"
for s in "$CLONE"/installers/work/*.sh; do
	check "ran installer ${s##*/}" grep -qF "Running ${s##*/}" "$SMOKE_LOG"
done
check "no downloads (vendor tools already installed)" not_grep '^curl ' "$SMOKE_LOG"
check "asked to sign commits with the new SSH key" grep -qF 'gum confirm Sign your git commits' "$SMOKE_LOG"
check "  ...and, on no, added no signing key with gh" not_grep '--type signing' "$SMOKE_LOG"
check "bash loads the aliases" [ "$(in_shell "$h" bash 'alias ll')" = "alias ll='ls -alh'" ]
check "bash gets the prompt" has_prompt "$h"
check "  ...which collapses the path" [ "$(prompt_var "$h" /usr/share/doc dir)" = /u/s/doc ]
mkdir -p "$h/.kube" && printf 'current-context: smoke-ctx\n' >"$h/.kube/config"
check "  ...shows the kube context" [ "$(prompt_var "$h" /tmp context)" = "smoke-ctx " ]
git init -q -b smoke-branch "$h/repo"
check "  ...and the git branch" [ "$(prompt_var "$h" "$h/repo" git)" = " smoke-branch" ]
check "bash gets the functions" [ "$(in_shell "$h" bash 'type -t fetchAll')" = function ]
check "bash gets the work aliases" [ "$(in_shell "$h" bash 'alias kc')" = "alias kc='kubectl'" ]
check "bash starts without errors" [ ! -s "$h/shell.err" ]
[ -s "$h/shell.err" ] && show "$h/shell.err"
check "a non-interactive bash (ssh host cmd) runs the rc block" [ "$(not_interactive "$h" 'printf %s "$ENVSETUP_ROOT"')" = "$h/.local/share/envsetup" ]
check "  ...but gets no functions" [ "$(not_interactive "$h" 'type -t fetchAll || echo none')" = none ]
check "  ...no aliases" [ "$(not_interactive "$h" 'alias ll >/dev/null 2>&1 || echo none')" = none ]
check "  ...but the exports (ssh host git commit gets EDITOR)" [ "$(not_interactive "$h" 'printf %s "${EDITOR:-}"')" = vim ]
check "  ...and prints nothing of its own (scp needs a silent shell)" [ "$(not_interactive "$h" 'echo marker')" = marker ]
check "values set before envsetup's block stay" [ "$(EDITOR=nano XDG_CONFIG_HOME=$h/mine MANPAGER=most in_shell "$h" bash 'printf %s "$EDITOR|$XDG_CONFIG_HOME|$MANPAGER"')" = "nano|$h/mine|most" ]
check "  ...and with no envsetup dir in that XDG_CONFIG_HOME, ~/.config/envsetup stays in use" [ "$(XDG_CONFIG_HOME=$h/mine in_shell "$h" bash 'alias kc')" = "alias kc='kubectl'" ]
check "git gets the shipped defaults" same_list "$(git config --file "$CLONE/git/gitconfig" alias.l)" "$(HOME=$h git config --global --includes alias.l)"
# CONTRIBUTING.md sets a requirement: the shell config adds less than 50 ms to each new shell (#126).
# work full loads the most files, so this scenario times it.
# Two copies of the home differ only in the envsetup block in their startup files.
# The copies keep the saved profile, so the shells load the same files as in $h.
# CI runners vary in speed.
# So the test starts each shell many times, takes turns between the homes, and compares the medians.
# The shells run without a terminal and exit before the first prompt.
# PATH has no direnv, zoxide, mise or fzf, so their hooks do not run.
runs=31 # an odd count, so one run is the median
linked=$(mktemp -d) bare=$(mktemp -d)
cp -a "$h/." "$linked"
cp -a "$h/." "$bare"
sed '/^# >>> envsetup >>>$/,/^# <<< envsetup <<<$/!d' "$h/.bashrc" >"$linked/.zshrc"
sed -i '/^# >>> envsetup >>>$/,/^# <<< envsetup <<<$/d' "$bare/.bashrc"
# An empty ~/.zshrc stops zsh from starting its new-user setup.
: >"$bare/.zshrc"
# startup_ms <home> <bash|zsh> prints how long a new interactive shell takes to start and exit, in ms.
startup_ms() {
	local t0=$EPOCHREALTIME
	HOME=$1 setsid -w "$2" -i -c exit </dev/null >/dev/null 2>&1
	echo $(((${EPOCHREALTIME/./} - ${t0/./}) / 1000))
}
median() { sort -n | sed -n "$((runs / 2 + 1))p"; }
# Both medians must exist, so two failed runs cannot pass.
under_50ms() { [[ -n "$1" && -n "$2" ]] && (($1 - $2 < 50)); }
# profile_is <home> <bash|zsh> <profile> passes when a new shell in <home> loads <profile>.
profile_is() { [[ "$(in_shell "$1" "$2" 'printf %s "${ENVSETUP_PROFILE:-none}"')" == "$3" ]]; }
for sh in bash zsh; do
	with=() without=()
	for ((i = 0; i < runs; i++)); do
		with+=("$(startup_ms "$linked" "$sh")")
		without+=("$(startup_ms "$bare" "$sh")")
	done
	a=$(printf '%s\n' "${with[@]}" | median) b=$(printf '%s\n' "${without[@]}" | median)
	check "$sh: the timed home loads the shell config" profile_is "$linked" "$sh" work
	check "  ...which adds less than 50 ms ($a ms with it, $b ms without)" under_50ms "$a" "$b"
	check "  ...(the other home does not load it)" profile_is "$bare" "$sh" none
done
# status runs setup.sh --status (#97).
# PATH has no gum, and the repo for the newest release is out of reach, as offline.
status() { HOME=$h ENVSETUP_REPO_URL=$W/no-repo PATH="$OFFLINE:/usr/bin:/bin" "$CLONE/setup.sh" --status >$W/status.out 2>&1; }
all_ok() { [ "$(grep -c '^ok ' $W/status.out)" = 7 ] && [ "$(wc -l <$W/status.out)" = 7 ]; }
check "--status exited 0" status
check "  ...printed 7 lines, each one ok" all_ok
((failures)) && show $W/status.out
mv "$OFFLINE/aws" $W/aws
check "--status without aws: exited 1" not status
mv $W/aws "$OFFLINE/aws"
check "  ...and named aws, which awscli.sh checks" grep -qx 'missing  aws is not on PATH. Select Run installers' $W/status.out
check "re-run exited 0" run_menu "$h" "Run everything" Quit
check "re-run didn't link twice" [ "$(count '# >>> envsetup >>>' "$h/.bashrc")" = 1 ]
((failures)) && show "$h/setup.out"

echo "== pruneBranches: deletes only what it lists, and keeps unmerged branches (#62)"
# This uses the work/full home above.
# The repo has main, 7 merged branches and an older unmerged branch.
r=$h/prune
git init -q -b main "$r"
pgit() { GIT_COMMITTER_DATE=$1 git -C "$r" -c user.name=smoke -c user.email=smoke@example.com "${@:2}"; }
pgit 2020-01-01T00:00:00 commit -q --allow-empty -m base
pgit 2020-01-02T00:00:00 switch -q -c wip
pgit 2020-01-02T00:00:00 commit -q --allow-empty -m wip
pgit 2020-01-03T00:00:00 switch -q main
pgit 2020-01-03T00:00:00 commit -q --allow-empty -m newer
for b in 1 2 3 4 5 6 7; do git -C "$r" branch "merged-$b"; done
branches() { git -C "$r" for-each-ref --format='%(refname:short)' refs/heads | wc -l; }
# Only the branches that are left count here.
# An unknown option returns 2, and set -e would stop on it.
prune() { in_shell "$h" bash "cd '$r' && pruneBranches $*" >/dev/null || true; }
check "(before: 9 branches)" [ "$(branches)" = 9 ]
prune --help
prune foo
prune --yes foo
check "--help and an unknown option delete nothing" [ "$(branches)" = 9 ]
prune 2 --dry-run --yes
check "--dry-run deletes nothing" [ "$(branches)" = 9 ]
prune 2
check "no answer to its question deletes nothing" [ "$(branches)" = 9 ]
prune 2 --yes
check "keeping 2 deleted the other 5 merged branches" [ "$(branches)" = 4 ]
check "  ...but not the unmerged one" git -C "$r" show-ref -q --verify refs/heads/wip
prune 2 --yes --force
check "--force deleted the unmerged one too" not git -C "$r" show-ref -q --verify refs/heads/wip
check "  ...and kept main and the 2 newest" [ "$(branches)" = 3 ]

echo "== work/lite: Run everything (no sudo: no packages, no installers)"
h=$(new_home)
check "exited 0" run_menu "$h" "Select profile" work lite "Run everything" Quit
check "linked ~/.bashrc" grep -qF '# >>> envsetup >>>' "$h/.bashrc"
check "no package installs" [ "$(count 'apt-get' "$SMOKE_LOG")" = 0 ]
check "no installers run" [ "$(count 'Running ' "$SMOKE_LOG")" = 0 ]
check "bash loads the aliases" [ "$(in_shell "$h" bash 'alias ll')" = "alias ll='ls -alh'" ]
check "bash skips exports" [ -z "$(in_shell "$h" bash 'printf %s "${EDITOR:-}"')" ]
check "bash gets the functions" [ "$(in_shell "$h" bash 'type -t fetchAll')" = function ]
check "bash still gets the envsetup command" [ "$(in_shell "$h" bash 'type -t envsetup')" = function ]
check "bash still gets the prompt" has_prompt "$h"

echo "== Configure git: an empty or cancelled answer saves no identity (#49)"
h=$(new_home)
identity() { git config --file "$1/.gitconfig" --get-regexp '^user\.' || echo none; }
SMOKE_INPUT=ESC check "cancelled: exited 0" run_menu "$h" "Select profile" work lite "Configure git" Quit
check "  ...saved no user.name or user.email" [ "$(identity "$h")" = none ]
check "  ...and said how to set them" grep -qF 'Skipped user.name. git needs it before your first commit' "$h/setup.out"
SMOKE_INPUT='  ' check "only spaces: exited 0" run_menu "$h" "Configure git" Quit
check "  ...saved none" [ "$(identity "$h")" = none ]
SMOKE_INPUT=not-an-email check "an email without @: exited 0" run_menu "$h" "Configure git" Quit
check "  ...saved the name, not the email" [ "$(identity "$h")" = "user.name not-an-email" ]
check "  ...and said why" grep -qF 'Skipped user.email: "not-an-email" is not an email address' "$h/setup.out"
((failures)) && show "$h/setup.out"

echo "== Set up SSH key: work lite, with gh (#93)"
h=$(new_home)
key=$h/.ssh/id_ed25519
signing() { git config --file "$1/.gitconfig" --get-regexp '^(gpg\.format|user\.signingkey|commit\.gpgsign)$' || echo none; }
before=$(snapshot "$h")
SETUP_ARGS=(--dry-run)
check "--dry-run: exited 0" run_menu "$h" "Select profile" work lite "Set up SSH key" Quit
SETUP_ARGS=()
check "  ...said it would create the key" grep -qF "would create the SSH key $key ($(id -un)@$HOSTNAME)" "$SMOKE_LOG"
check "  ...and offer it to gh" grep -qF 'would ask to add it to your GitHub account with gh' "$SMOKE_LOG"
check "  ...and add it as a signing key on yes" grep -qF 'would add it to your GitHub account as a signing key with gh, if you say yes to both questions' "$SMOKE_LOG"
check "  ...ran no ssh-keygen or gh" not_grep '^\(ssh-keygen\|gh\) ' "$SMOKE_LOG"
check "  ...and changed nothing" [ "$(snapshot "$h")" = "$before" ]
CONFIRMS=(yes yes) # add it with gh; sign commits with it
check "exited 0" run_menu "$h" "Select profile" work lite "Set up SSH key" Quit
CONFIRMS=()
check "created the key, named for this machine" grep -qxF "ssh-ed25519 AAAAsmoke $(id -un)@$HOSTNAME" "$key.pub"
check "added it with gh" grep -qxF "gh ssh-key add $key.pub --title $(id -un)@$HOSTNAME" "$SMOKE_LOG"
check "  ...and as a signing key, once you said yes to signing" grep -qxF "gh ssh-key add $key.pub --type signing --title $(id -un)@$HOSTNAME signing" "$SMOKE_LOG"
check "set git to sign commits with it" [ "$(signing "$h" | tr '\n' ' ')" = "gpg.format ssh user.signingkey $key.pub commit.gpgsign true " ]
before=$(snapshot "$h")
check "a second run exited 0" run_menu "$h" "Set up SSH key" Quit
check "  ...ran no ssh-keygen" not_grep '^ssh-keygen ' "$SMOKE_LOG"
check "  ...and changed nothing" [ "$(snapshot "$h")" = "$before" ]
SETUP_ARGS=(--uninstall) CONFIRMS=(yes yes) # remove; keep the key
check "--uninstall exited 0" run_menu "$h"
SETUP_ARGS=() CONFIRMS=()
check "  ...asked about the key" grep -qF 'gum confirm Keep ~/.ssh/id_ed25519?' "$SMOKE_LOG"
check "  ...kept it, as answered" grep -qxF smoke-private-key "$key"
check "  ...and removed the signing settings" [ "$(signing "$h")" = none ]
((failures)) && show "$h/setup.out"

echo "== Set up SSH key: no to gh, yes to signing"
h=$(new_home)
key=$h/.ssh/id_ed25519
CONFIRMS=(no yes)
check "exited 0" run_menu "$h" "Select profile" work lite "Set up SSH key" Quit
CONFIRMS=()
check "  ...set git to sign commits with the key" [ "$(git config --file "$h/.gitconfig" user.signingkey)" = "$key.pub" ]
check "  ...added no signing key" not_grep '--type signing' "$SMOKE_LOG"
check "  ...and called no gh at all" not_grep '^gh ' "$SMOKE_LOG"
check "  ...and said where to add the signing key" grep -qF 'Add the public key as a signing key at https://github.com/settings/keys' "$SMOKE_LOG"
((failures)) && show "$h/setup.out"

echo "== Set up SSH key: no gh, then uninstall deletes it when told to"
h=$(new_home)
key=$h/.ssh/id_ed25519
mv "$OFFLINE/gh" $W/gh
check "exited 0" run_menu "$h" "Select profile" work lite "Run everything" Quit
mv $W/gh "$OFFLINE/gh"
check "created the key in Run everything" [ -f "$key" ]
check "  ...and showed it, with where to add it" grep -qF 'Add this public key at https://github.com/settings/keys' "$SMOKE_LOG"
check "  ...left git signing alone when told no" [ "$(signing "$h")" = none ]
SETUP_ARGS=(--uninstall) CONFIRMS=(yes no) # remove; don't keep the key
check "--uninstall exited 0" run_menu "$h"
SETUP_ARGS=() CONFIRMS=()
check "  ...deleted the key and ~/.ssh" none_exist "$key" "$key.pub" "$h/.ssh"
check "  ...and its marker" [ ! -e "$h/.config/envsetup" ]
((failures)) && show "$h/setup.out"

echo "== Set up SSH key: signing settings of your own are left alone"
h=$(new_home)
git config --file "$h/.gitconfig" user.signingkey SMOKEGPGKEY
git config --file "$h/.gitconfig" commit.gpgsign true
mine="user.signingkey SMOKEGPGKEY commit.gpgsign true "
check "exited 0" run_menu "$h" "Select profile" work lite "Set up SSH key" Quit
check "  ...created the key" [ -f "$h/.ssh/id_ed25519" ]
check "  ...didn't offer to sign with it" not_grep 'gum confirm Sign your git commits' "$SMOKE_LOG"
check "  ...or add it to GitHub as a signing key" not_grep '--type signing' "$SMOKE_LOG"
check "  ...and said why" grep -qF 'git already has signing settings' "$SMOKE_LOG"
check "  ...and kept your settings" [ "$(signing "$h" | tr '\n' ' ')" = "$mine" ]
SETUP_ARGS=(--uninstall) CONFIRMS=(yes yes)
check "--uninstall exited 0" run_menu "$h"
SETUP_ARGS=() CONFIRMS=()
check "  ...and kept your settings" [ "$(signing "$h" | tr '\n' ' ')" = "$mine" ]
((failures)) && show "$h/setup.out"

echo "== Set up SSH key: a key of your own is left alone"
h=$(new_home)
mkdir -m 700 "$h/.ssh"
echo mine >"$h/.ssh/id_ed25519"
check "exited 0" run_menu "$h" "Select profile" work lite "Set up SSH key" Quit
check "  ...ran no ssh-keygen" not_grep '^ssh-keygen ' "$SMOKE_LOG"
check "  ...and kept the key as it was" [ "$(cat "$h/.ssh/id_ed25519")" = mine ]
SETUP_ARGS=(--uninstall) CONFIRMS=(yes)
check "--uninstall exited 0" run_menu "$h"
SETUP_ARGS=() CONFIRMS=()
check "  ...didn't ask about the key" not_grep 'Keep ~/.ssh/id_ed25519' "$SMOKE_LOG"
check "  ...and kept it" [ "$(cat "$h/.ssh/id_ed25519")" = mine ]
((failures)) && show "$h/setup.out"

echo "== config.sh with a failed command, then with a syntax error (#51)"
h=$(new_home)
mkdir -p "$h/.config/envsetup"
printf 'ENVSETUP_EXTRAS=(lazygit)\nfalse\n' >"$h/.config/envsetup/config.sh"
check "a failed command: exited 0" run_menu "$h" "Select profile" work lite "Configure git" Quit
check "  ...warned once (the menu loads config.sh each time it shows)" [ "$(count 'the command on line 2 failed' "$h/setup.out")" = 1 ]
printf 'ENVSETUP_EXTRAS=(lazygit\n' >"$h/.config/envsetup/config.sh"
check "a syntax error: exited 0" run_menu "$h" "Configure git" Quit
check "  ...warned once, with the line" [ "$(count 'did not load completely (line 1: unexpected EOF' "$h/setup.out")" = 1 ]
# This is the README's own example.
# On this work machine, the test on the last line is false, so `source` returns 1.
# That is not an error.
printf 'ENVSETUP_EXTRAS=(lazygit)\n[[ $ENVSETUP_PROFILE == home ]] && ENVSETUP_EXTRAS+=(k9s)\n' >"$h/.config/envsetup/config.sh"
check "a last line of [[ false ]] && ...: exited 0" run_menu "$h" "Configure git" Quit
check "  ...and no warning" not_grep 'failed. envsetup continues' "$h/setup.out"
((failures)) && show "$h/setup.out"

echo "== an ENVSETUP_STATE for another \$HOME (as a test with a throwaway \$HOME gets it) is not used"
h=$(new_home)
f=$W/foreign-state
ENVSETUP_STATE=$f ENVSETUP_STATE_HOME=$W/foreign-home check "exited 0" run_menu "$h" "Select profile" work lite Quit
check "saved the profile in this \$HOME's state dir" [ "$(cat "$h/.config/envsetup/profile" 2>/dev/null)" = work ]
check "  ...and nothing in the other one" [ ! -e "$f" ]
((failures)) && show "$h/setup.out"

echo "== work/lite with XDG_CONFIG_HOME set, and odd paths: envsetup keeps its state and the shell copy there"
h=$(new_home)
# Both paths contain a space, ", $(...) and a backtick, and the block must quote them (#46).
# If a shell ran $(exit 1) or `false`, ENVSETUP_ROOT would not be the path.
x="$h/xdg config \"q\" \$(touch $h/ran) \`touch $h/ran\`"
odd="$W/env setup \"q\" \$(exit 1) \`false\`"
XDG_CONFIG_HOME=$x XDG_DATA_HOME=$odd check "exited 0" run_menu "$h" "Select profile" work lite "Run everything" Quit
check "saved the profile in \$XDG_CONFIG_HOME/envsetup" [ "$(cat "$x/envsetup/profile" 2>/dev/null)" = work ]
check "  ...and nothing in ~/.config/envsetup" [ ! -e "$h/.config/envsetup" ]
# Lite mode loads no exports.
# Without the saved mode, a shell would load full mode's EDITOR=vim.
check "a shell with the same XDG_CONFIG_HOME finds it (lite: no EDITOR)" [ "$(XDG_CONFIG_HOME=$x in_shell "$h" bash 'printf %s "${EDITOR:-none}"')" = none ]
check "  ...and so does a shell without XDG_CONFIG_HOME (ssh, cron): the rc block keeps the dir" [ "$(in_shell "$h" bash 'printf %s "${EDITOR:-none}|$ENVSETUP_STATE"')" = "none|$x/envsetup" ]
check "  ...and the copy of shell/ in \$XDG_DATA_HOME" [ "$(in_shell "$h" bash 'printf %s "$ENVSETUP_ROOT"')" = "$odd/envsetup" ]
check "  ...and loads its aliases" [ "$(in_shell "$h" bash 'alias ll')" = "alias ll='ls -alh'" ]
quoted() { [ ! -s "$h/shell.err" ] && [ ! -e "$h/ran" ]; }
check "  ...which the rc block quotes: no errors, and nothing in the paths ran" quoted
SETUP_ARGS=(--uninstall) CONFIRMS=(yes)
XDG_CONFIG_HOME=$x XDG_DATA_HOME=$odd check "--uninstall exits 0" run_menu "$h"
SETUP_ARGS=() CONFIRMS=()
check "  ...and removed both" none_exist "$x/envsetup" "$odd/envsetup"
((failures)) && show "$h/setup.out"

echo "== home: Run everything (bash; zsh is opt-in)"
h=$(new_home)
check "exited 0" run_menu "$h" "Select profile" home "Run everything" Quit
check "linked ~/.bashrc once" [ "$(count '# >>> envsetup >>>' "$h/.bashrc")" = 1 ]
check "installed common + home packages" same_list "$(expected home)" "$(installed)"
check "ran installer docker.sh" grep -qF "Running docker.sh" "$SMOKE_LOG"
check "  ...a no-op with docker already there" not_grep '^curl .*docker' "$SMOKE_LOG"
check "bash loads the aliases" [ "$(in_shell "$h" bash 'alias ll')" = "alias ll='ls -alh'" ]
check "bash starts without errors" [ ! -s "$h/shell.err" ]
check "left zsh alone" none_exist "$h/.oh-my-zsh" "$h/.zshrc"
check "didn't ask about the login shell" not_grep '^gum confirm Set zsh' "$SMOKE_LOG"
check "installed them all at once" [ "$(grep -c '^apt-get install -y ' "$SMOKE_LOG")" = 1 ]

echo "== --status and Check status: ok after Run everything, then a removed block (#97)"
before=$(snapshot "$h")
check "--status exited 0 without gum" status
check "  ...printed 7 lines, each one ok" all_ok
check "  ...said the newest release is unknown" grep -qF 'newest release: unknown' $W/status.out
check "  ...and changed nothing in \$HOME" [ "$(snapshot "$h")" = "$before" ]
((failures)) && show $W/status.out
sed -i '/^# >>> envsetup >>>$/,/^# <<< envsetup <<<$/d' "$h/.bashrc"
check "without the ~/.bashrc block: exited 1" not status
check "  ...and said the block is missing" grep -qx "missing  $h/.bashrc has no envsetup block. Select Link shell config" $W/status.out
check "  ...on the only missing line" [ "$(grep -c '^missing ' $W/status.out)" = 1 ]
check "Check status in the menu: exited 0" run_menu "$h" "Check status" Quit
check "  ...and said the block is missing" grep -qF "missing  $h/.bashrc has no envsetup block" "$h/setup.out"

echo "== home: Run everything, docker missing: its installer reuses the session's package lists"
h=$(new_home)
mv "$OFFLINE/docker" $W/docker
check "exited 0" run_menu "$h" "Select profile" home "Run everything" Quit
mv $W/docker "$OFFLINE/docker"
check "docker.sh installed docker.io" grep -qx 'apt-get install -y docker.io' "$SMOKE_LOG"
check "refreshed package lists once" [ "$(count 'apt-get update' "$SMOKE_LOG")" = 1 ]

echo "== home: Set up zsh + oh-my-zsh (menu)"
check "exited 0" run_menu "$h" "Set up zsh + oh-my-zsh" Quit
check "installed oh-my-zsh" [ -d "$h/.oh-my-zsh" ]
check "asked about the login shell" grep -q '^gum confirm Set zsh as your default login shell' "$SMOKE_LOG"
check "kept the oh-my-zsh .zshrc" grep -qF 'stand-in for the oh-my-zsh theme' "$h/.zshrc"
check "linked ~/.zshrc once" [ "$(count '# >>> envsetup >>>' "$h/.zshrc")" = 1 ]
check "zsh loads the aliases" [ "$(in_shell "$h" zsh 'alias ll')" = "ll='ls -alh'" ]
check "zsh keeps the theme prompt" [ "$(in_shell "$h" zsh 'print -r -- $PS1')" = '%n@%m %# ' ]
check "zsh starts without errors" [ ! -s "$h/shell.err" ]
[ -s "$h/shell.err" ] && show "$h/shell.err"
check "re-run exited 0" run_menu "$h" "Set up zsh + oh-my-zsh" Quit
check "re-run didn't link twice" [ "$(count '# >>> envsetup >>>' "$h/.zshrc")" = 1 ]
check "zsh hooks zoxide when it's installed" [ "$(PATH=$HOOKS:$PATH in_shell "$h" zsh 'typeset -f __zoxide_z >/dev/null && echo hooked')" = hooked ]
check "  ...without errors" [ ! -s "$h/shell.err" ]

echo "== ENVSETUP_EXTRAS and tool hooks"
h=$(new_home)
mkdir -p "$h/.config/envsetup"
echo 'ENVSETUP_EXTRAS=(lazygit nope)' >"$h/.config/envsetup/config.sh"
check "exited 0" run_menu "$h" "Select profile" work full "Run everything" Quit
check "the mode picker counts the extra" described "$(n_installers work)" "runs $(($(n_installers work) + 1)) installers"
check "ran the extra's installer" grep -qF "Running lazygit.sh" "$SMOKE_LOG"
check "  ...a no-op with lazygit already there" not_grep '^curl .*lazygit' "$SMOKE_LOG"
check "named the extra it has no installer for" grep -qF 'no installer for "nope"' "$h/setup.out"
check "bash hooks direnv when it's installed" [ "$(PATH=$HOOKS:$PATH in_shell "$h" bash 'typeset -f _direnv_hook >/dev/null && echo hooked')" = hooked ]
check "  ...and zoxide" [ "$(PATH=$HOOKS:$PATH in_shell "$h" bash 'typeset -f __zoxide_z >/dev/null && echo hooked')" = hooked ]
check "  ...without errors" [ ! -s "$h/shell.err" ]
check "no hooks for tools that aren't installed" [ "$(in_shell "$h" bash 'typeset -f _direnv_hook >/dev/null || echo none')" = none ]
((failures)) && show "$h/setup.out"

echo "== work/lite: ENVSETUP_SHELL=zsh makes Run everything set up zsh too"
h=$(new_home)
mkdir -p "$h/.config/envsetup"
echo 'ENVSETUP_SHELL=zsh' >"$h/.config/envsetup/config.sh"
check "exited 0" run_menu "$h" "Select profile" work lite "Run everything" Quit
check "linked ~/.bashrc" [ "$(count '# >>> envsetup >>>' "$h/.bashrc")" = 1 ]
check "  ...and ~/.zshrc" [ "$(count '# >>> envsetup >>>' "$h/.zshrc")" = 1 ]
check "installed oh-my-zsh" [ -d "$h/.oh-my-zsh" ]
check "  ...without installing packages (zsh was already there)" [ "$(count 'apt-get' "$SMOKE_LOG")" = 0 ]
((failures)) && show "$h/setup.out"

echo "== a zsh login shell gets ~/.zshrc linked, without oh-my-zsh"
h=$(new_home)
SHELL=/usr/bin/zsh check "exited 0" run_menu "$h" "Select profile" work lite "Run everything" Quit
check "linked ~/.bashrc" [ "$(count '# >>> envsetup >>>' "$h/.bashrc")" = 1 ]
check "  ...and ~/.zshrc" [ "$(count '# >>> envsetup >>>' "$h/.zshrc")" = 1 ]
check "  ...without installing oh-my-zsh" [ ! -e "$h/.oh-my-zsh" ]
check "zsh loads the aliases" [ "$(in_shell "$h" zsh 'alias ll')" = "ll='ls -alh'" ]
check "  ...without errors" [ ! -s "$h/shell.err" ]
SETUP_ARGS=(--uninstall) CONFIRMS=(yes yes)
SHELL=/usr/bin/zsh check "--uninstall exits 0" run_menu "$h"
SETUP_ARGS=() CONFIRMS=()
check "  ...unlinked both" none_exist_in '# >>> envsetup >>>' "$h/.bashrc" "$h/.zshrc"
check "  ...and didn't offer to change a login shell it didn't set" not_grep 'Keep zsh as your login shell' "$SMOKE_LOG"
((failures)) && show "$h/setup.out"

echo "== shell.d: your own shell files (#105)"
h=$(new_home)
d=$h/.config/envsetup/shell.d
SETUP_ARGS=(--dry-run)
check "--dry-run Link shell config: exited 0" run_menu "$h" "Select profile" work lite "Link shell config" Quit
SETUP_ARGS=()
check "  ...said it would create shell.d" grep -qF "would create $d" "$SMOKE_LOG"
check "  ...and didn't" [ ! -e "$d" ]
# A zsh login shell gets ~/.zshrc linked too, so a real zsh loads shell.d.
SHELL=/usr/bin/zsh check "Link shell config: exited 0" run_menu "$h" "Select profile" work lite "Link shell config" Quit
check "  ...created shell.d" [ -d "$d" ]
check "bash starts with the empty folder" [ "$(in_shell "$h" bash 'echo started')" = started ]
check "  ...without errors" [ ! -s "$h/shell.err" ]
check "zsh starts with the empty folder" [ "$(in_shell "$h" zsh 'echo started')" = started ]
check "  ...without errors" [ ! -s "$h/shell.err" ]
echo 'mine=cfg' >"$h/.config/envsetup/config.sh"
for f in 10-a.sh 20-b.bash 30-z.zsh 50-c.sh README 50-c.sh~; do echo "mine+=${f:3:1}" >"$d/$f"; done
echo 'if (' >"$d/40-broken.sh"
check "bash loads .sh and .bash files in name order, after config.sh" [ "$(in_shell "$h" bash 'printf %s "$mine"')" = cfgabc ]
check "  ...and names the broken file" grep -qF 40-broken.sh "$h/shell.err"
check "zsh loads .sh and .zsh files in name order, after config.sh" [ "$(in_shell "$h" zsh 'printf %s "$mine"')" = cfgazc ]
check "  ...and names the broken file" grep -qF 40-broken.sh "$h/shell.err"
check "a non-interactive bash loads no file from shell.d" [ "$(not_interactive "$h" 'printf %s "$mine"')" = cfg ]
SMOKE_WRITE='mine+=p' SMOKE_INPUT=60-pasted check "Paste config, shell file: exited 0" run_menu "$h" "Paste config" shell Quit
check "  ...saved the text as 60-pasted.sh" [ "$(cat "$d/60-pasted.sh" 2>/dev/null)" = 'mine+=p' ]
check "  ...and the next new shell loads it" [ "$(in_shell "$h" bash 'printf %s "$mine"')" = cfgabcp ]
SMOKE_WRITE='mine+=q' SMOKE_INPUT=60-pasted.sh run_menu "$h" "Paste config" shell Quit || true
check "a name that exists asks to replace it" grep -qF "gum confirm --default=false Replace 60-pasted.sh?" "$SMOKE_LOG"
check "  ...and the default answer keeps the old file" [ "$(cat "$d/60-pasted.sh")" = 'mine+=p' ]
CONFIRMS=(yes)
SMOKE_WRITE='mine+=q' SMOKE_INPUT=60-pasted.sh run_menu "$h" "Paste config" shell Quit || true
CONFIRMS=()
check "  ...and yes replaces it" [ "$(cat "$d/60-pasted.sh")" = 'mine+=q' ]
echo 'mine+=t' >"$h/target.sh"
ln -s "$h/target.sh" "$d/65-link.sh"
CONFIRMS=(yes)
SMOKE_WRITE='mine+=l' SMOKE_INPUT=65-link.sh run_menu "$h" "Paste config" shell Quit || true
CONFIRMS=()
check "yes to replace a link saves a plain file" [ ! -L "$d/65-link.sh" ]
check "  ...with the new text" [ "$(cat "$d/65-link.sh")" = 'mine+=l' ]
check "  ...and leaves the file that the link pointed to" [ "$(cat "$h/target.sh")" = 'mine+=t' ]
rm -f "$d/65-link.sh" "$h/target.sh"
SMOKE_WRITE=$'alias x=y\nexit 0' SMOKE_INPUT=70-exit.sh run_menu "$h" "Paste config" shell Quit || true
check "a shell file that runs exit is not saved" none_exist "$d/70-exit.sh"
check "  ...and says why" grep -qF 'stops before its end in bash' "$SMOKE_LOG"
SMOKE_WRITE=$'if true\nfi' SMOKE_INPUT=70-bad.sh run_menu "$h" "Paste config" shell Quit || true
check "a shell file with an error is not saved" none_exist "$d/70-bad.sh"
check "  ...and the error shows the line number" grep -qF 'line 2: syntax error' "$SMOKE_LOG"
SMOKE_WRITE='mine+=x' SMOKE_INPUT=../x.sh run_menu "$h" "Paste config" shell Quit || true
check "a name with a / is rejected" grep -qF '"../x.sh" is not a file name' "$SMOKE_LOG"
check "  ...and nothing is saved outside shell.d" none_exist "$h/.config/envsetup/x.sh"
SETUP_ARGS=(--dry-run)
SMOKE_WRITE='mine+=x' SMOKE_INPUT=80-dry.sh run_menu "$h" "Paste config" shell Quit || true
SETUP_ARGS=()
check "a dry-run paste says it would save the shell file" grep -qF "would save the text as $d/80-dry.sh" "$SMOKE_LOG"
check "  ...and saves nothing" none_exist "$d/80-dry.sh"
before=$(snapshot "$d")
SHELL=/usr/bin/zsh check "Link shell config again: exited 0" run_menu "$h" "Link shell config" Quit
check "  ...and left shell.d unchanged" [ "$(snapshot "$d")" = "$before" ]
# The answers: remove, yes; keep config.sh, yes; keep shell.d, yes.
SETUP_ARGS=(--uninstall) CONFIRMS=(yes yes yes)
check "--uninstall exits 0" run_menu "$h"
check "  ...asked to keep shell.d" grep -qF "gum confirm Keep $d?" "$SMOKE_LOG"
check "  ...kept it when told to" [ "$(snapshot "$d")" = "$before" ]
check "  ...and listed it" grep -qF "your shell files: $d" "$SMOKE_LOG"
# The answers: remove, yes; keep config.sh, no; keep shell.d, no.
CONFIRMS=(yes no no)
check "--uninstall again exits 0" run_menu "$h"
SETUP_ARGS=() CONFIRMS=()
check "  ...deleted shell.d when told to" [ ! -e "$d" ]
check "  ...and the state folder" [ ! -e "$h/.config/envsetup" ]
((failures)) && show "$h/setup.out"

echo "== explaining itself"
h=$(new_home)
check "--help works before gum is installed" help_ok "$h"
check "an unknown option is rejected, not ignored" rejects_unknown "$h"
check "  ...without writing anything" [ ! -e "$h/.config" ]
run_menu "$h" Quit
check "a first run shows a welcome" grep -qF 'Welcome to envsetup' "$SMOKE_LOG"
w=$(n_expected work) wi=$(n_installers work) hm=$(n_expected home)
# Answer with whole lines, the way gum returns a selected label.
run_menu "$h" "Select profile" "work  bash · (as gum returns it)" "lite  no sudo: (as gum returns it)" Quit
check "work is described from its config" described "$w" "work  bash · $w packages · $wi installers ("
check "home is described from its config" described "$hm" "home  bash · $hm packages · $(n_installers home) installer (docker)"
check "modes say what needs sudo" described "$w" "full  uses sudo: installs $w packages and runs $wi installers"
check "a picked line is saved as just its name" [ "$(cat "$h/.config/envsetup/profile")/$(cat "$h/.config/envsetup/mode")" = work/lite ]
run_menu "$h" Quit
check "no welcome once a profile is saved" not_grep 'Welcome to envsetup' "$SMOKE_LOG"
h=$(new_home)
mkdir -p "$h/.config/envsetup"
printf 'ENVSETUP_SHELL=zsh\nENVSETUP_SKIP=(%s)\n' "$(expected home | head -1)" >"$h/.config/envsetup/config.sh"
run_menu "$h" "Select profile" ESC
check "descriptions follow the user's config.sh" described "$hm" "home  zsh + oh-my-zsh · $((hm - 1)) packages"

echo "== --dry-run: home, Run everything"
h=$(new_home)
before=$(snapshot "$h")
SETUP_ARGS=(--dry-run)
check "exited 0" run_menu "$h" "Select profile" home "Run everything" Quit
SETUP_ARGS=()
check "said it would link ~/.bashrc" grep -qF "would add a 5-line block to $h/.bashrc" "$SMOKE_LOG"
check "  ...and nothing about zsh" not_grep 'would .*\(oh-my-zsh\|zshrc\)' "$SMOKE_LOG"
check "said it would ask for a git identity" grep -qF 'would ask for your git user.name' "$SMOKE_LOG"
check "said it would install common + home packages" described "$hm" "would install $hm packages"
check "said it would create an SSH key" grep -qF "would create the SSH key $h/.ssh/id_ed25519" "$SMOKE_LOG"
check "ran nothing that changes the machine" not_grep '^\(apt-get\|curl\|chsh\|ssh-keygen\) ' "$SMOKE_LOG"
check "left \$HOME exactly as it was" [ "$(snapshot "$h")" = "$before" ]
touch "$h/.bashrc"
echo "# control" >>"$h/.bashrc"
check "  ...(control: the snapshot does notice a change)" [ "$(snapshot "$h")" != "$before" ]
((failures)) && show "$h/setup.out"

echo "== --dry-run: config edits last only for the session"
h=$(new_home)
before=$(snapshot "$h")
printf '#!/bin/sh\necho ENVSETUP_SHELL=zsh >>"$1"\n' >$W/editor
chmod +x $W/editor
export EDITOR=$W/editor
SETUP_ARGS=(--dry-run)
run_menu "$h" "Edit config" "Select profile" ESC Quit || true
SETUP_ARGS=()
unset EDITOR
check "the edit applied within the session" described "$hm" "home  zsh + oh-my-zsh · $hm packages"
check "  ...and nothing was saved" [ "$(snapshot "$h")" = "$before" ]

echo "== Paste config, Edit config and --config: check the text, then show the changes"
h=$(new_home)
c=$h/.config/envsetup/config.sh
SMOKE_WRITE='ENVSETUP_EXTRAS+=(lazygit k9s)' check "Paste config: exited 0" run_menu "$h" "Paste config" settings Quit
check "  ...added the text to the end of config.sh" [ "$(cat "$c" 2>/dev/null)" = 'ENVSETUP_EXTRAS+=(lazygit k9s)' ]
check "  ...and showed the changed setting" grep -qxF 'gum style Extras: +lazygit +k9s' "$SMOKE_LOG"
SMOKE_WRITE=$'ENVSETUP_SKIP+=(tig)\r' run_menu "$h" "Paste config" settings Quit || true
want=$'ENVSETUP_EXTRAS+=(lazygit k9s)\nENVSETUP_SKIP+=(tig)'
check "a paste from Windows loses its \\r" [ "$(cat "$c")" = "$want" ]
SMOKE_WRITE=$'ENVSETUP_SHELL=zsh\nfi' run_menu "$h" "Paste config" settings Quit || true
check "a paste with an error leaves config.sh as it was" [ "$(cat "$c")" = "$want" ]
check "  ...and shows the line number" grep -qF 'line 2: syntax error' "$SMOKE_LOG"
SMOKE_WRITE=$' \n\t' run_menu "$h" "Paste config" settings Quit || true
check "an empty paste saves nothing" [ "$(cat "$c")" = "$want" ]
check "  ...and says so" grep -qF 'The text is empty' "$SMOKE_LOG"
SMOKE_WRITE='exit 0' run_menu "$h" "Paste config" settings Quit || true
check "a paste that runs exit saves nothing" [ "$(cat "$c")" = "$want" ]
check "  ...and says why" grep -qF 'would stop before its end' "$SMOKE_LOG"
printf 'if true; then\n' >>"$c"
SMOKE_WRITE='ENVSETUP_SHELL=zsh' run_menu "$h" "Paste config" settings Quit || true
check "a paste onto a config.sh with an error saves nothing" [ "$(cat "$c")" = "$want"$'\nif true; then' ]
check "  ...and names the line in config.sh" grep -qF 'config.sh already has an error, so envsetup saved nothing. Select Edit config to fix it: line 4: syntax error' "$SMOKE_LOG"
printf '%s\n' "$want" >"$c"
before=$(snapshot "$h")
SETUP_ARGS=(--dry-run)
SMOKE_WRITE='ENVSETUP_SKIP+=(btop)' run_menu "$h" "Paste config" settings Quit || true
SETUP_ARGS=()
check "a dry-run paste shows the changes" grep -qxF 'gum style Skip: +btop' "$SMOKE_LOG"
check "  ...and saves nothing" [ "$(snapshot "$h")" = "$before" ]
mkdir -p $W/nano
printf '#!/bin/sh\necho "nano $*" >>"$SMOKE_LOG"\necho ENVSETUP_XDG_NINJA=1 >>"$1"\n' >$W/nano/nano
chmod +x $W/nano/nano
EDITOR='' PATH=$W/nano:$PATH run_menu "$h" "Edit config" Quit || true
check "Edit config without \$EDITOR opens nano" grep -qxF "nano $c" "$SMOKE_LOG"
check "  ...and shows the changed setting" grep -qxF 'gum style XDG ninja: +1 -0' "$SMOKE_LOG"
printf '#!/bin/sh\necho fi >>"$1"\n' >$W/editor
EDITOR=$W/editor run_menu "$h" "Edit config" Quit || true
check "an edit with an error shows the line number" grep -qF "$c has an error. Select Edit config to fix it: line $(wc -l <"$c"): syntax error" "$SMOKE_LOG"
h=$(new_home)
c=$h/.config/envsetup/config.sh
printf 'ENVSETUP_SHELL=zsh\nfi\n' >$W/bad.sh
SETUP_ARGS=(--config "$W/bad.sh")
check "--config with an error: exits non-zero" not run_menu "$h" Quit
check "  ...adds nothing" none_exist "$c"
check "  ...and shows the line number" grep -qF 'line 2: syntax error' "$SMOKE_LOG"
SETUP_ARGS=(--config "$W/bad.sh" --uninstall)
check "--config with --uninstall: exits non-zero" not run_menu "$h" Quit
check "  ...and says why" grep -qF 'do not work together' "$h/setup.out"
printf 'ENVSETUP_SHELL=zsh\n' >$W/mine.sh
SETUP_ARGS=(--config "$W/mine.sh")
check "--config: exited 0" run_menu "$h" Quit
SETUP_ARGS=()
check "  ...added the file's text to config.sh" [ "$(cat "$c" 2>/dev/null)" = ENVSETUP_SHELL=zsh ]
check "  ...and showed the changed setting" grep -qxF 'gum style Shell: +zsh -bash' "$SMOKE_LOG"

echo "== A renamed setting in config.sh: ask, then migrate (#124)"
# The shipped ENVSETUP_RENAMED is empty, so a copy of the clone gets a test item.
M=$W/renamed
cp -a "$CLONE" "$M"
sed -i 's/^ENVSETUP_RENAMED=()$/ENVSETUP_RENAMED=(ENVSETUP_OLD_SHELL=ENVSETUP_SHELL)/' "$M/lib/config.sh"
check "  ...(control: the copy has the test item)" grep -qxF 'ENVSETUP_RENAMED=(ENVSETUP_OLD_SHELL=ENVSETUP_SHELL)' "$M/lib/config.sh"
h=$(new_home)
c=$h/.config/envsetup/config.sh
mkdir -p "${c%/*}"
# The first line has a byte that is not valid UTF-8, before the old name (Latin-1 text).
old=$'# caf\xe9\nENVSETUP_OLD_SHELL=zsh\n# ENVSETUP_OLD_SHELLS stays'
printf '%s\n' "$old" >"$c"
check "the shipped list is empty, so it asks nothing" run_menu "$h" Quit
check "  ...and leaves config.sh as it was" [ "$(cat "$c")" = "$old" ]
check "  ...and never asks" not grep -qF 'gum confirm' "$SMOKE_LOG"
before=$(snapshot "$h")
SETUP_ARGS=(--dry-run)
SETUP=$M/setup.sh check "--dry-run: exited 0" run_menu "$h" Quit
SETUP_ARGS=()
check "  ...said it would ask" grep -qF "would ask to rename these settings in $c: ENVSETUP_OLD_SHELL → ENVSETUP_SHELL" "$SMOKE_LOG"
check "  ...did not ask" not grep -qF 'gum confirm' "$SMOKE_LOG"
check "  ...and saved nothing" [ "$(snapshot "$h")" = "$before" ]
CONFIRMS=(no)
SETUP=$M/setup.sh check "no: exited 0" run_menu "$h" "Select profile" home Quit
check "  ...asked first" grep -qF 'gum confirm --default=false Some settings in '"$c"' have a new name: ENVSETUP_OLD_SHELL → ENVSETUP_SHELL.' "$SMOKE_LOG"
check "  ...left config.sh as it was" [ "$(cat "$c")" = "$old" ]
check "  ...and still read the old name" described "$hm" "home  zsh + oh-my-zsh · $hm packages"
CONFIRMS=(yes)
SETUP=$M/setup.sh check "yes: exited 0" run_menu "$h" Quit
check "  ...renamed only that name" [ "$(cat "$c")" = $'# caf\xe9\nENVSETUP_SHELL=zsh\n# ENVSETUP_OLD_SHELLS stays' ]
SETUP=$M/setup.sh check "a second run: exited 0" run_menu "$h" Quit
check "  ...and asked nothing" not grep -qF 'gum confirm' "$SMOKE_LOG"
CONFIRMS=()

echo "== Preview everything (normal session): work/full"
h=$(new_home)
check "exited 0" run_menu "$h" "Select profile" work full "Preview everything" Quit
check "said it would install common + work packages" described "$w" "would install $w packages"
check "said it would run the work installers" described "$wi" "would run $wi installer scripts"
check "ran nothing that changes the machine" not_grep '^\(apt-get\|curl\|chsh\|ssh-keygen\) ' "$SMOKE_LOG"
check "left ~/.bashrc as it was" cmp -s /etc/skel/.bashrc "$h/.bashrc"
check "still saved the profile you picked" [ "$(cat "$h/.config/envsetup/profile" 2>/dev/null)" = work ]

echo "== install.sh: the newest release by default, or the one asked for (and passes --version to setup.sh)"
# Every commit on this origin is the code under test.
# The releases come later.
R=$W/releases
git init -q -b main "$R"
git -C "$CLONE" archive HEAD | tar -x -C "$R"
rel() { git -C "$R" -c user.name=smoke -c user.email=smoke@example.com "$@"; }
# release <message> [tag] adds a commit to the origin's main, with the given tag.
release() {
	rel add -A
	rel commit -q --allow-empty -m "$1"
	if [ -n "${2:-}" ]; then rel tag -a "$2" -m "$2"; fi
}
# install_version <ENVSETUP_VERSION> runs install.sh from that origin, then setup.sh --version.
# gum is not on PATH, because --version must work before gum is installed.
install_version() {
	ENVSETUP_VERSION=$1 ENVSETUP_REPO_URL=$R TMPDIR=$TMP PATH=/usr/bin:/bin \
		bash "$SRC/install.sh" --version >$W/version.out 2>&1
}
reports() { [ "$(tail -n 1 $W/version.out)" = "$1" ]; }
fails() { ! "$@"; }
release "feat: first"
check "with no releases yet, exits 0" install_version ""
check "  ...and runs main" reports "$(rel rev-parse --short HEAD)"
rel tag -a v1.0.0 -m v1.0.0
release "feat: second" v1.1.0
release "fix: third" v1.2.0-rc.1
check "again, now there are releases" install_version ""
check "  ...runs the newest one, skipping the pre-release" reports v1.1.0
check "ENVSETUP_VERSION=1.0.0 exits 0" install_version 1.0.0
check "  ...and runs v1.0.0" reports v1.0.0
check "ENVSETUP_VERSION=main exits 0" install_version main
check "  ...and runs the branch's newest commit" reports v1.2.0-rc.1
check "an unknown version fails" fails install_version 9.9.9
check "  ...listing the releases" grep -qF '  v1.1.0' $W/version.out
check "  ...and deletes its download" left_nothing
((failures)) && show $W/version.out
# The copy of shell/ matches the release that linked it last.
from_releases() { ENVSETUP_REPO_URL=$R TMPDIR=$TMP bash "$SRC/install.sh" "$@"; }
h=$(new_home)
ENVSETUP_VERSION=1.1.0 SETUP=from_releases check "Link shell config from v1.1.0: exits 0" run_menu "$h" "Link shell config" Quit
check "  ...records v1.1.0" [ "$(cat "$h/.local/share/envsetup/version" 2>/dev/null)" = v1.1.0 ]
echo "alias smoke-release='v1.2.0'" >>"$R/shell/shared/aliases.sh"
release "fix: fourth" v1.2.0
SETUP=from_releases check "a new release upstream: exits 0" run_menu "$h" "Link shell config" Quit
check "  ...records it" [ "$(cat "$h/.local/share/envsetup/version" 2>/dev/null)" = v1.2.0 ]
check "  ...and new shells get its shell config" [ "$(in_shell "$h" bash 'alias smoke-release')" = "alias smoke-release='v1.2.0'" ]
check "  ...and deletes its download" left_nothing
((failures)) && show "$h/setup.out"

echo "== an rc block from before #86, which loads shell/ from a checkout, is rewritten"
# old_install <home> creates ~/envsetup and the block that linked it.
# Then it adds one line of the user's own.
old_install() {
	cp -a "$CLONE" "$1/envsetup"
	printf '%s\n' '# >>> envsetup >>>' "export ENVSETUP_ROOT=$1/envsetup" \
		"export ENVSETUP_STATE=$1/.config/envsetup ENVSETUP_STATE_HOME=$1" \
		'[ -f "$ENVSETUP_ROOT/shell/init.sh" ] && source "$ENVSETUP_ROOT/shell/init.sh"' \
		'# <<< envsetup <<<' '# a line of my own' >>"$1/.bashrc"
}
h=$(new_home)
old_install "$h"
before=$(snapshot "$h")
SETUP_ARGS=(--dry-run)
check "--dry-run: exited 0" run_menu "$h" "Link shell config" Quit
SETUP_ARGS=()
check "  ...said it would rewrite the block" grep -qF "would rewrite the envsetup block in $h/.bashrc" "$SMOKE_LOG"
check "  ...and delete ~/envsetup, as answered" grep -qF "would delete $h/envsetup" "$SMOKE_LOG"
check "  ...and changed nothing" [ "$(snapshot "$h")" = "$before" ]
check "exited 0" run_menu "$h" "Link shell config" Quit
check "rewrote the block to load the copy" grep -qxF "export ENVSETUP_ROOT=$h/.local/share/envsetup" "$h/.bashrc"
check "  ...once, in place" [ "$(count '# >>> envsetup >>>' "$h/.bashrc")/$(tail -n 1 "$h/.bashrc")" = "1/# a line of my own" ]
check "asked \"Keep ~/envsetup?\"" grep -qF "gum confirm Keep $h/envsetup?" "$SMOKE_LOG"
check "  ...and deleted it when told to" [ ! -e "$h/envsetup" ]
check "bash loads the aliases" [ "$(in_shell "$h" bash 'alias ll')" = "alias ll='ls -alh'" ]
check "  ...without errors" [ ! -s "$h/shell.err" ]
h=$(new_home)
old_install "$h"
CONFIRMS=(yes)
check "answering keep: exited 0" run_menu "$h" "Link shell config" Quit
CONFIRMS=()
check "  ...kept ~/envsetup" [ -f "$h/envsetup/setup.sh" ]
check "  ...and still rewrote the block" grep -qxF "export ENVSETUP_ROOT=$h/.local/share/envsetup" "$h/.bashrc"
((failures)) && show "$h/setup.out"

echo "== update from the last 0.x release, with the same config.sh (#125)"
# The last 0.x release is the newest v0.* tag below the commit under test.
# So the choice needs no edit at each release.
# It also stays the same from 1.0.0 on.
# HEAD^ leaves out a tag on HEAD itself, so a release commit does not update to itself.
# CI fetches every tag for this (fetch-depth: 0 in ci.yml), so the test stays offline.
old=$(git -C "$CLONE" describe --tags --abbrev=0 --match 'v0.*' --exclude '*-*' HEAD^ 2>/dev/null || true)
check "(found the last 0.x release: ${old:-none, so fetch the tags})" [ -n "$old" ]
if [ -n "$old" ]; then
	h=$(new_home)
	mkdir -p "$h/.config/envsetup"
	printf '%s\n' 'ENVSETUP_SHELL=zsh' 'ENVSETUP_SKIP=(tig)' 'ENVSETUP_GIT_CONFIG+=("alias.smoke=status")' \
		"ENVSETUP_REPO_URL=$SRC" >"$h/.config/envsetup/config.sh"
	cp "$h/.config/envsetup/config.sh" $W/config.before
	echo '# a line of my own' >>"$h/.bashrc"
	echo 'my own notes' >"$h/notes.txt"
	# The user installed the old release with its own install.sh.
	git -C "$CLONE" show "$old:install.sh" >$W/old-install.sh
	old_release() { ENVSETUP_VERSION=$old ENVSETUP_REPO_URL=$SRC TMPDIR=$TMP bash $W/old-install.sh "$@"; }
	SETUP=old_release check "install $old, Run everything: exited 0" run_menu "$h" "Select profile" home "Run everything" Quit
	check "  ...recorded $old" same_list "$old" "$(cat "$h/.local/share/envsetup/version" 2>/dev/null)"
	# The user then updates with the envsetup command from the old release.
	SETUP_ARGS=(update)
	SETUP=envsetup_bash check "envsetup update to the commit under test, Run everything: exited 0" run_menu "$h" "Run everything" Quit
	SETUP_ARGS=()
	check "  ...recorded the new release" same_list "$(PATH=/usr/bin:/bin "$CLONE/setup.sh" --version)" "$(cat "$h/.local/share/envsetup/version" 2>/dev/null)"
	# CONFIRMS is empty, so the fake gum answers "no" to any question.
	# A later item in ENVSETUP_RENAMED (#124) then leaves config.sh as it is.
	# The smoke scenario for #124 covers the "yes" answer.
	check "  ...kept config.sh the same" cmp -s $W/config.before "$h/.config/envsetup/config.sh"
	check "  ...kept the user's line in ~/.bashrc" grep -qxF '# a line of my own' "$h/.bashrc"
	check "  ...and the user's own file" [ "$(cat "$h/notes.txt")" = 'my own notes' ]
	# The new release must still apply each setting in the old config.sh.
	check "  ...still skips the package in ENVSETUP_SKIP" same_list "$(expected home | grep -vx tig)" "$(installed)"
	check "  ...still adds the git setting in ENVSETUP_GIT_CONFIG" [ "$(HOME=$h git config --global --includes --get alias.smoke)" = status ]
	check "  ...and still links ~/.zshrc for ENVSETUP_SHELL=zsh" grep -qF "Already linked in $h/.zshrc" "$h/setup.out"
	# bash prints "alias ll=...", and zsh prints "ll=...".
	has_ll() { [[ "$(in_shell "$1" "$2" 'alias ll')" == *"ll='ls -alh'" ]]; }
	for sh in bash zsh; do
		check "$sh loads the aliases" has_ll "$h" $sh
		check "  ...without errors" [ ! -s "$h/shell.err" ]
		[ -s "$h/shell.err" ] && show "$h/shell.err"
	done
	# Requirement 3: a second run changes nothing.
	before=$(snapshot "$h")
	SETUP_ARGS=(update)
	SETUP=envsetup_bash check "envsetup update again, Run everything: exited 0" run_menu "$h" "Run everything" Quit
	SETUP_ARGS=()
	check "  ...and changed nothing" [ "$(snapshot "$h")" = "$before" ]
	((failures)) && show "$h/setup.out"
fi

echo "== --uninstall: work/full, declined and dry-run first"
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
check "  ...and the copy of shell/" grep -qF "would delete $h/.local/share/envsetup" "$SMOKE_LOG"
check "  ...and changes nothing" [ "$(snapshot "$h")" = "$before" ]
gc=$h/.config/envsetup/gitconfig
check "(before: git includes envsetup's file)" [ "$(includes "$h")" = "$gc" ]
check "(before: a profile is saved)" [ -f "$h/.config/envsetup/profile" ]
mkdir -p "$h/.kube" && printf 'current-context: smoke-ctx\n' >"$h/.kube/config"
prompt_var "$h" /tmp context >/dev/null
check "(before: the prompt cached the kube context)" [ -f "$h/.cache/envsetup/kube-context" ]
mkdir -p "$h/no-repos"
in_shell "$h" bash 'cd ~/no-repos && fetchAll --quiet >/dev/null; wait' >/dev/null
check "(before: fetchAll --quiet wrote its log)" grep -qF 'Fetched all repositories.' "$h/.cache/envsetup/fetchAll.log"
SETUP_ARGS=(--uninstall) CONFIRMS=(yes)
check "exited 0" run_menu "$h"
check ".bashrc is byte-for-byte what it was" cmp -s /etc/skel/.bashrc "$h/.bashrc"
check "removed the git include" [ -z "$(includes "$h")" ]
check "kept the git identity" [ "$(git config --file "$h/.gitconfig" user.name)" = "Smoke Test" ]
check "removed envsetup's saved state" [ ! -e "$h/.config/envsetup" ]
check "  ...and the copy of shell/" [ ! -e "$h/.local/share/envsetup" ]
check "removed the prompt's cache and the fetchAll log" none_exist "$h/.cache/envsetup/kube-context" "$h/.cache/envsetup/fetchAll.log" "$h/.cache/envsetup"
check "bash is back to the distro's aliases" [ "$(in_shell "$h" bash 'alias ll')" = "alias ll='ls -alF'" ]
check "didn't touch the login shell" not_grep '^chsh ' "$SMOKE_LOG"
before=$(snapshot "$h")
check "a second --uninstall exits 0" run_menu "$h"
check "  ...and changes nothing" [ "$(snapshot "$h")" = "$before" ]
SETUP_ARGS=() CONFIRMS=()
((failures)) && show "$h/setup.out"

echo "== Uninstall from the menu: home on zsh, with a config.sh"
h=$(new_home)
mkdir -p "$h/.config/envsetup"
echo 'alias smoke=true' >"$h/.config/envsetup/config.sh"
CONFIRMS=(no no yes) # no to the SSH key's two questions, yes to make zsh the login shell
run_menu "$h" "Select profile" home "Run everything" "Set up zsh + oh-my-zsh" Quit
check "(before: ~/.zshrc is linked)" grep -qF '# >>> envsetup >>>' "$h/.zshrc"
check "(before: noted that it switched the login shell)" [ -f "$h/.config/envsetup/chsh" ]
# The answers: remove, yes; keep config.sh, no; keep the SSH key, no; keep zsh as the login shell, no.
CONFIRMS=(yes no no no)
SHELL=/usr/bin/zsh check "exited 0" run_menu "$h" Uninstall
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

echo "== ENVSETUP_CONFIG_REPO: config.sh from your own git repo (#94)"
cfg=$W/config-repo
cgit() { git -C "$cfg" -c user.name=smoke -c user.email=smoke@example.com "$@"; }
git init -q -b main "$cfg"
echo 'ENVSETUP_PACKAGES=(smoke-from-repo)' >"$cfg/config.sh"
cgit add config.sh
cgit commit -q -m config
h=$(new_home)
st=$h/.config/envsetup
before=$(snapshot "$h")
SETUP_ARGS=(--dry-run)
ENVSETUP_CONFIG_REPO=$cfg check "--dry-run: exited 0" run_menu "$h" Quit
SETUP_ARGS=()
check "  ...said it would clone the repo" grep -qF "would clone $cfg into $st/repo" "$SMOKE_LOG"
check "  ...and link config.sh to it" grep -qF "would link $st/config.sh to $st/repo/config.sh" "$SMOKE_LOG"
check "  ...and changed nothing" [ "$(snapshot "$h")" = "$before" ]
ENVSETUP_CONFIG_REPO=$cfg SETUP=curl_bash check "curl | ENVSETUP_CONFIG_REPO=<repo> bash: exited 0" run_menu "$h" "Select profile" home "Install packages" Quit
check "  ...cloned the repo" same_commit "$cfg" "$st/repo"
check "  ...linked config.sh to it" [ "$(readlink "$st/config.sh")" = "$st/repo/config.sh" ]
check "  ...and used its settings on the first run" same_list smoke-from-repo "$(installed)"
# git pull writes its own notes into .git, for example FETCH_HEAD.
# So this check leaves out the clone's .git folder.
but_git() {
	(
		cd "$h" || exit 1
		find . -path ./.config/envsetup/repo/.git -prune -o ! -name setup.out -print | sort
		find . -path ./.config/envsetup/repo/.git -prune -o -type f ! -name setup.out -exec md5sum {} + | sort
	) | md5sum
}
before=$(but_git)
CONFIRMS=(yes) # pull
check "a second run, with nothing new in the repo: exited 0" run_menu "$h" Quit
CONFIRMS=()
check "  ...asked to pull first" grep -qF "gum confirm Pull your config repo ($st/repo)" "$SMOKE_LOG"
check "  ...and changed nothing outside the clone's .git" [ "$(but_git)" = "$before" ]
echo 'ENVSETUP_PACKAGES=(smoke-pulled)' >"$cfg/config.sh"
cgit commit -q -am update
check "a second run, after a new commit, no to the pull: exited 0" run_menu "$h" Quit
check "  ...did not pull" not same_commit "$cfg" "$st/repo"
CONFIRMS=(yes) # pull
check "  ...yes to the pull: exited 0" run_menu "$h" "Install packages" Quit
CONFIRMS=()
check "  ...pulled the repo, without ENVSETUP_CONFIG_REPO" same_commit "$cfg" "$st/repo"
check "  ...and used the new settings" same_list smoke-pulled "$(installed)"
ENVSETUP_CONFIG_REPO=$W/other check "another ENVSETUP_CONFIG_REPO than the clone's: exited 0" run_menu "$h" Quit
check "  ...warned" grep -qF "ENVSETUP_CONFIG_REPO is $W/other, but $st/repo comes from $cfg" "$SMOKE_LOG"
# A dry-run edit must change the session's copy, not the clone behind the link.
dirty() { [ -n "$(git -C "$st/repo" status --porcelain)" ]; }
printf '#!/bin/sh\necho "# smoke edit" >>"$1"\n' >$W/edit-append
chmod +x $W/edit-append
echo '# sentinel' >>"$st/config.sh"
check "(an edit through the link shows in git status)" dirty
git -C "$st/repo" checkout -q -- config.sh
check "(and the clone is clean again)" not dirty
SETUP_ARGS=(--dry-run)
EDITOR=$W/edit-append check "--dry-run Edit config with a linked config.sh: exited 0" run_menu "$h" "Edit config" Quit
SETUP_ARGS=()
check "  ...left the clone clean" not dirty
SETUP_ARGS=(--dry-run)
SMOKE_WRITE='# smoke paste' check "--dry-run Paste config with a linked config.sh: exited 0" run_menu "$h" "Paste config" settings Quit
SETUP_ARGS=()
check "  ...left the clone clean" not dirty
SMOKE_WRITE='# smoke paste' check "Paste config with a linked config.sh: exited 0" run_menu "$h" "Paste config" settings Quit
check "  ...added the text to the clone's config.sh" [ "$(tail -n 1 "$st/repo/config.sh")" = '# smoke paste' ]
check "  ...and said to commit and push it" grep -qF 'Commit and push your edits there' "$SMOKE_LOG"
git -C "$st/repo" checkout -q -- config.sh
SETUP_ARGS=(--uninstall) CONFIRMS=(yes yes no) # remove; keep the repo; keep config.sh, no
check "--uninstall: exited 0" run_menu "$h"
SETUP_ARGS=() CONFIRMS=()
check "  ...asked about the repo" grep -qF "gum confirm Keep $st/repo?" "$SMOKE_LOG"
check "  ...kept it, as answered" same_commit "$cfg" "$st/repo"
check "  ...and removed the link, as answered" not [ -L "$st/config.sh" ]
((failures)) && show "$h/setup.out"

echo "== ENVSETUP_CONFIG_REPO with a config.sh of your own (#94)"
h=$(new_home)
st=$h/.config/envsetup
mkdir -p "$st"
echo 'alias mine=true' >"$st/config.sh"
CONFIRMS=(yes) # keep your own config.sh
ENVSETUP_CONFIG_REPO=$cfg check "keep it: exited 0" run_menu "$h" Quit
CONFIRMS=()
check "  ...asked first" grep -qF "gum confirm Keep your own $st/config.sh?" "$SMOKE_LOG"
check "  ...still cloned the repo" same_commit "$cfg" "$st/repo"
kept_mine() { [ ! -L "$st/config.sh" ] && grep -qxF "alias mine=true" "$st/config.sh"; }
check "  ...and kept config.sh" kept_mine
check "a second run: exited 0" run_menu "$h" Quit
check "  ...did not ask again" [ "$(count 'Keep your own' "$SMOKE_LOG")" = 0 ]
check "  ...nor ask to pull" [ "$(count 'Pull your config repo' "$SMOKE_LOG")" = 0 ]
check "  ...and kept config.sh" kept_mine
h=$(new_home)
st=$h/.config/envsetup
mkdir -p "$st"
echo 'alias mine=true' >"$st/config.sh"
CONFIRMS=(no) # replace it
ENVSETUP_CONFIG_REPO=$cfg check "replace it: exited 0" run_menu "$h" Quit
check "  ...linked config.sh to the repo" [ "$(readlink "$st/config.sh")" = "$st/repo/config.sh" ]
check "  ...and moved the old text to config.sh.bak" grep -qxF 'alias mine=true' "$st/config.sh.bak"
check "  ...and said so" grep -qF "Moved your old config.sh to $st/config.sh.bak" "$SMOKE_LOG"
SETUP_ARGS=(--uninstall) CONFIRMS=(yes no yes) # remove; keep the repo, no; keep config.sh, yes
check "--uninstall, delete the repo but keep config.sh: exited 0" run_menu "$h"
SETUP_ARGS=() CONFIRMS=()
check "  ...deleted the repo" [ ! -e "$st/repo" ]
check "  ...and kept a copy of its config.sh" same_list "$(cat "$cfg/config.sh")" "$(cat "$st/config.sh" 2>/dev/null)"
check "  ...as a file, not a link" not [ -L "$st/config.sh" ]
check "  ...kept config.sh.bak" grep -qxF 'alias mine=true' "$st/config.sh.bak"
check "  ...and listed it" grep -qF "your old config: $st/config.sh.bak" "$SMOKE_LOG"
h=$(new_home)
st=$h/.config/envsetup
ENVSETUP_CONFIG_REPO=$cfg run_menu "$h" Quit || true
SETUP_ARGS=(--uninstall) CONFIRMS=(yes no no) # remove; keep the repo, no; keep config.sh, no
check "--uninstall, delete both: exited 0" run_menu "$h"
SETUP_ARGS=() CONFIRMS=()
check "  ...deleted the repo and config.sh, as answered" [ ! -e "$st" ]
h=$(new_home)
ENVSETUP_CONFIG_REPO=$W/no-such-repo check "a repo that can't be cloned: exited 0" run_menu "$h" Quit
check "  ...warned" grep -qF "Couldn't clone $W/no-such-repo" "$SMOKE_LOG"
check "  ...and still reached the menu" grep -q '^gum choose Select profile' "$SMOKE_LOG"
((failures)) && show "$h/setup.out"

echo "== a package that can't be installed doesn't stop the rest"
h=$(new_home)
mkdir -p "$h/.config/envsetup"
echo 'ENVSETUP_PACKAGES+=(smoke-conflict)' >"$h/.config/envsetup/config.sh"
check "exited 0: back to the menu, then Quit" run_menu "$h" "Select profile" work full "Run everything" Quit
check "tried them all at once first" grep -q '^apt-get install -y .* smoke-conflict$' "$SMOKE_LOG"
check "  ...then one at a time" [ "$(grep -c '^apt-get install -y [^ ]*$' "$SMOKE_LOG")" = "$(($(n_expected work) + 1))" ]
check "  ...and named the one that failed" grep -qF "Couldn't install: smoke-conflict" "$h/setup.out"
check "said the step didn't finish" grep -qF "That step didn't finish" "$SMOKE_LOG"
check "still ran the installers after it" grep -qF "Running kubectl.sh" "$SMOKE_LOG"
((failures)) && show "$h/setup.out"

echo "== Move dotfiles to XDG dirs (ENVSETUP_XDG_NINJA=1, offline copy of xdg-ninja)"
# These notes use xdg-ninja's real format.
# The notes are a move with an export, a move only, and a dotfile that the user's .bashrc mentions.
# Two more notes are unsafe, and envsetup must leave both alone.
# One exports BASH_ENV, which makes every bash script run the file.
# The other has a path that leads out of the XDG folder.
mkdir -p $W/xdg-ninja/programs
cat >$W/xdg-ninja/programs/docker.json <<'JSON'
{"name": "docker", "files": [{"path": "$HOME/.docker", "movable": true,
 "help": "Export the following environment variables:\n\n```bash\nexport DOCKER_CONFIG=\"$XDG_CONFIG_HOME\"/docker\n```\n"}]}
JSON
cat >$W/xdg-ninja/programs/htop.json <<'JSON'
{"name": "htop", "files": [{"path": "$HOME/.htoprc", "movable": true,
 "help": "Supported by default.\n\nYou can move the file to _$XDG_CONFIG_HOME/htop/htoprc_.\n"}]}
JSON
cat >$W/xdg-ninja/programs/wget.json <<'JSON'
{"name": "wget", "files": [{"path": "$HOME/.wgetrc", "movable": true,
 "help": "```bash\nexport WGETRC=\"$XDG_CONFIG_HOME/wgetrc\"\n```\n"}]}
JSON
cat >$W/xdg-ninja/programs/unsafe.json <<'JSON'
{"name": "unsafe", "files": [{"path": "$HOME/.envrc-unsafe", "movable": true,
 "help": "```bash\nexport BASH_ENV=\"$XDG_CONFIG_HOME\"/envrc-unsafe\n```\n"},
 {"path": "$HOME/.outside", "movable": true,
 "help": "```bash\nexport OUTSIDE_RC=\"$XDG_CONFIG_HOME\"/../../outside\n```\n"}]}
JSON
git -C $W/xdg-ninja init -q && git -C $W/xdg-ninja add . && git -C $W/xdg-ninja -c user.name=smoke -c user.email=smoke@example.com commit -qm notes
export ENVSETUP_XDG_NINJA_URL=file://$W/xdg-ninja
h=$(new_home)
mkdir -p "$h/.docker" "$h/.config/envsetup"
echo '{"auths": {}}' >"$h/.docker/config.json"
echo 'color_scheme=1' >"$h/.htoprc"
echo 'tries=3' >"$h/.wgetrc"
echo 'echo unsafe' >"$h/.envrc-unsafe"
echo 'outside' >"$h/.outside"
echo 'alias wget="wget --config ~/.wgetrc"' >>"$h/.bashrc"
echo 'ENVSETUP_XDG_NINJA=1' >"$h/.config/envsetup/config.sh"
before=$(snapshot "$h")
SETUP_ARGS=(--dry-run)
check "--dry-run exits 0" run_menu "$h" "Move dotfiles to XDG dirs" Quit
check "  ...says it would fetch the notes" grep -qF "would download xdg-ninja's notes" "$SMOKE_LOG"
check "  ...and changes nothing" [ "$(snapshot "$h")" = "$before" ]
SETUP_ARGS=() CONFIRMS=(no no yes) # no to the SSH key's two questions, yes to the moves
check "Run everything exited 0" run_menu "$h" "Select profile" work full "Run everything" Quit
check "moved ~/.htoprc (program reads the XDG path)" cmp -s <(echo 'color_scheme=1') "$h/.config/htop/htoprc"
check "moved ~/.docker" [ -f "$h/.config/docker/config.json" ]
check "  ...out of \$HOME" [ ! -e "$h/.docker" ]
check "  ...and new shells get DOCKER_CONFIG" [ "$(in_shell "$h" bash 'printf %s "$DOCKER_CONFIG"')" = "$h/.config/docker" ]
check "    ...non-interactive ones too" [ "$(not_interactive "$h" 'printf %s "$DOCKER_CONFIG"')" = "$h/.config/docker" ]
check "left ~/.wgetrc: .bashrc references it" [ -f "$h/.wgetrc" ]
check "  ...and said why" grep -qF 'leaving ~/.wgetrc (wget): referenced from' "$h/setup.out"
check "left the dotfile a note exports as BASH_ENV" [ -f "$h/.envrc-unsafe" ]
check "  ...and exported no BASH_ENV" [ "$(grep -c BASH_ENV "$h/.config/envsetup/xdg.sh")" = 0 ]
check "left the dotfile a note moves out of the XDG dir" [ -f "$h/.outside" ]
check "  ...and said both need manual steps" [ "$(grep -cE 'leaving ~/\.(envrc-unsafe|outside) \(unsafe\): needs manual steps' "$h/setup.out")" = 2 ]
mkdir "$h/.docker" # a program without DOCKER_CONFIG creates it again (cron, a launcher)
SETUP_ARGS=(--uninstall) CONFIRMS=(yes yes)
check "--uninstall with ~/.docker made again exits non-zero" not run_menu "$h"
check "  ...moved ~/.htoprc back" cmp -s <(echo 'color_scheme=1') "$h/.htoprc"
check "  ...left ~/.config/docker where it is" [ -f "$h/.config/docker/config.json" ]
check "  ...said why" grep -qF "Leaving $h/.config/docker where it is: $h/.docker exists again" "$SMOKE_LOG"
check "  ...and kept it in the list of moves" grep -qF "$h/.config/docker" "$h/.config/envsetup/xdg-moves"
rmdir "$h/.docker"
check "uninstalling again exits 0" run_menu "$h"
SETUP_ARGS=() CONFIRMS=()
check "  ...moved ~/.docker back" [ -f "$h/.docker/config.json" ]
check "  ...and removed the exports and the notes" none_exist "$h/.config/envsetup/xdg.sh" "$h/.cache/envsetup"
unset ENVSETUP_XDG_NINJA_URL
((failures)) && show "$h/setup.out"

echo "== work/full: Run installers updates only the tools that envsetup installed (#96)"
# A copy of the clone pins kubectl to the fake curl's kubectl.
# The record says that envsetup installed kubectl 1.0.0 and the pinned helm.
# envsetup did not install terraform, which the fakes put on PATH.
c=$W/clone-96
cp -a "$CLONE" "$c"
pins=$c/installers/versions.txt
k_pin=$(awk '$1 == "kubectl" { print $2 }' "$pins")
helm_pin=$(awk '$1 == "helm" { print $2 }' "$pins")
k_sha=$(printf '#!/bin/sh\necho smoke-kubectl\n' | sha256sum | cut -d' ' -f1)
sed -i "s/^kubectl .*/kubectl $k_pin linux-amd64=$k_sha linux-arm64=$k_sha/" "$pins"
h=$(new_home)
rec=$h/.local/state/envsetup/installed
mkdir -p "${rec%/*}"
printf 'kubectl 1.0.0\nhelm %s\n' "$helm_pin" >"$rec"
SETUP=$c/setup.sh check "Preview everything: exited 0" run_menu "$h" "Select profile" work full "Preview everything" Quit
check "  ...listed the update" grep -qF "would update kubectl 1.0.0 → $k_pin" "$SMOKE_LOG"
check "  ...and only that one" [ "$(count 'would update ' "$SMOKE_LOG")" = 1 ]
check "  ...downloaded nothing" not_grep '^curl ' "$SMOKE_LOG"
check "  ...and left the record as it was" [ "$(cat "$rec")" = "$(printf 'kubectl 1.0.0\nhelm %s' "$helm_pin")" ]
SETUP=$c/setup.sh check "Run installers: exited 0" run_menu "$h" "Run installers" Quit
# line_of <text> prints the number of the first log line with the text.
line_of() { grep -nF -- "$1" "$SMOKE_LOG" | head -n 1 | cut -d: -f1; }
listed_first() {
	local u r
	u=$(line_of "kubectl 1.0.0 → $k_pin") r=$(line_of 'Running ')
	[ -n "$u" ] && [ -n "$r" ] && [ "$u" -lt "$r" ]
}
only_kubectl() { [ "$(grep -c '^curl ' "$SMOKE_LOG")" = 1 ] && grep -q '^curl .*dl\.k8s\.io/release/v'"$k_pin"'/' "$SMOKE_LOG"; }
check "  ...listed the update before the first installer ran" listed_first
check "  ...downloaded only the pinned kubectl" only_kubectl
check "  ...installed the pinned kubectl" [ "$(/usr/local/bin/kubectl)" = smoke-kubectl ]
check "  ...recorded its version" grep -qxF "kubectl $k_pin" "$rec"
check "  ...kept helm's line" grep -qxF "helm $helm_pin" "$rec"
check "  ...and recorded no terraform, which you installed" not_grep '^terraform ' "$rec"
SETUP=$c/setup.sh check "Run installers again: exited 0" run_menu "$h" "Run installers" Quit
check "  ...listed no update and downloaded nothing" not_grep '→\|^curl ' "$SMOKE_LOG"
SETUP_ARGS=(--uninstall) CONFIRMS=(yes no)
SETUP=$c/setup.sh check "--uninstall: exited 0" run_menu "$h"
SETUP_ARGS=() CONFIRMS=()
check "  ...deleted the record" none_exist "$rec" "${rec%/*}"
check "  ...and kept the tool" [ -x /usr/local/bin/kubectl ]
((failures)) && show "$h/setup.out"
rm -rf /usr/local/bin/kubectl "$c"

echo "== download verification (lib/common.sh), offline"
# install_release gets a file:// URL from a fake curl that only copies local files.
# gpg_verify checks tests/fixtures/signed.txt with the real gpgv.
# It uses a temporary key made for this test, and nobody kept the secret half of that key.
v=$W/verify
mkdir -p "$v/bin"
printf '#!/bin/sh\nfor a; do out=$url; url=$a; done\n[ "$out" != "${out#-}" ] && exit 2\ncp "${url#file://}" "$out"\n' >"$v/bin/curl"
chmod +x "$v/bin/curl"
printf '#!/bin/sh\necho smoke-verified\n' >"$v/smoke-good"
cp "$v/smoke-good" "$v/smoke-bad"
good_sha=$(sha256sum "$v/smoke-good" | cut -d' ' -f1)
verify() { env PATH="${VPATH:-$v/bin:$PATH}" ENVSETUP_ROOT="$CLONE" "$BASH" -c 'source "$ENVSETUP_ROOT/lib/common.sh" && "$@"' _ "$@" >"$v/out" 2>&1; }
check "install_release installs a download that matches its checksum" verify envsetup::install_release "file://$v/smoke-good" "$good_sha" smoke-good
check "  ...the binary it installed runs" [ "$(/usr/local/bin/smoke-good 2>&1)" = smoke-verified ]
echo tampered >>"$v/smoke-bad"
check "install_release refuses one that doesn't" not verify envsetup::install_release "file://$v/smoke-bad" "$good_sha" smoke-bad
check "  ...says why" grep -qF "smoke-bad does not match its published checksum" "$v/out"
check "  ...and installs nothing" [ ! -e /usr/local/bin/smoke-bad ]
check "  ...nor with an empty checksum (none was published)" not verify envsetup::install_release "file://$v/smoke-good" "" smoke-empty
pins=$CLONE/installers/versions.txt
pins_version() { verify envsetup::pin kubectl && same_list "$(awk '$1 == "kubectl" { print $2 }' "$pins")" "$(cat "$v/out")"; }
pins_sha() { verify envsetup::pin kubectl linux-arm64 && grep -qxE '[0-9a-f]{64}' "$v/out"; }
check "pin gives a tool's version from installers/versions.txt" pins_version
check "  ...and the sha256 for a platform" pins_sha
check "  ...fails for a platform with none" not verify envsetup::pin kubectl linux-riscv64
check "  ...saying which" grep -qF "no checksum of kubectl for linux-riscv64" "$v/out"
check "  ...fails for a name it doesn't pin" not verify envsetup::pin no-such-tool
# Every name that the code pins is in the file.
# A name with hashes has an amd64 hash and an arm64 hash.
pins_complete() {
	local n names
	names=$(grep -rhoE 'envsetup::pin [a-z0-9]+' "$CLONE/installers" "$CLONE/lib" | cut -d' ' -f2 | sort -u)
	[ "$(echo "$names" | wc -w)" -gt 10 ] || return 1
	for n in $names; do
		verify envsetup::pin "$n" || return 1
		awk -v n="$n" '$1 == n && NF > 2' "$pins" | grep -q . || continue
		verify envsetup::pin "$n" linux-amd64 && verify envsetup::pin "$n" linux-arm64 || return 1
	done
}
check "every name the installers pin is in versions.txt" pins_complete
fx=$CLONE/tests/fixtures
fpr=33BA29D63A94A1F8D01A594286EFD1F2522F6FD0
check "gpg_verify passes a good signature by the pinned key" verify envsetup::gpg_verify "$fx/signed.txt" "$fx/signed.txt.sig" "$fx/smoke-key.asc" "$fpr"
sed 's/smoke test/smoke tesT/' "$fx/signed.txt" >"$v/signed.txt"
check "  ...fails a file with one byte changed" not verify envsetup::gpg_verify "$v/signed.txt" "$fx/signed.txt.sig" "$fx/smoke-key.asc" "$fpr"
check "  ...says why" grep -qF "signed.txt has no valid signature by $fpr" "$v/out"
check "  ...fails another key's fingerprint, even a prefix of the right one" not verify envsetup::gpg_verify "$fx/signed.txt" "$fx/signed.txt.sig" "$fx/smoke-key.asc" "${fpr%?}"
mkdir -p "$v/nogpg"
for t in mktemp base64 rm; do ln -sf "$(command -v "$t")" "$v/nogpg/$t"; done
VPATH=$v/nogpg check "  ...fails closed with neither gpgv nor gpg" not verify envsetup::gpg_verify "$fx/signed.txt" "$fx/signed.txt.sig" "$fx/smoke-key.asc" "$fpr"
check "  ...saying what to install" grep -qF "to check the signature of signed.txt. Install gnupg." "$v/out"

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
