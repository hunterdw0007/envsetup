#!/usr/bin/env bash
# This script runs as root inside one distro container, after inside.sh.
# It uses envsetup the way a tester would: as users with sudo who are not root.
# It uses real package installs and downloads.
# Only gum's menus are scripted, so the menu can run without a person.
# Every phase writes a line to /report/<slug>/summary.tsv, and the logs go next to it.
set -uo pipefail # no -e, so each phase reports its own result and the next phase still runs

pm=$1
slug=${DISTRO_SLUG:?}
out=/report/$slug
mkdir -p "$out"
summary=$out/summary.tsv
: >"$summary"
stubs=/opt/envsetup-stubs

# result <phase> <PASS|WARN|FAIL> <detail>
result() {
	printf '%s\t%s\t%s\t%s\n' "$slug" "$1" "$2" "${3//$'\n'/ }" >>"$summary"
	printf '  %-4s %-22s %s\n' "$2" "$1" "$3"
}

# This creates a user who is not root and has sudo without a password.
# sudo keeps the hook's environment (proxy, CA).
mkuser() {
	useradd -m -s /bin/bash "$1"
	printf '%s ALL=(ALL) NOPASSWD: ALL\nDefaults env_keep += "DEBIAN_FRONTEND %s"\n' "$1" "${DISTROS_KEEP_ENV:-}" >"/etc/sudoers.d/$1"
	chmod 0440 "/etc/sudoers.d/$1"
}

# as <user> <command> runs the command for that user in a bash that acts like a login shell.
# It runs on the terminal, because install.sh and setup.sh read answers from /dev/tty.
as() {
	local user=$1
	shift
	# shellcheck disable=SC2024 # root opens /dev/tty for the user's process on purpose
	sudo -u "$user" -H env "PATH=$stubs:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
		"SMOKE_LOG=/tmp/$user/gum.log" "SMOKE_CHOICES=/tmp/$user/choices" "SMOKE_CONFIRMS=/tmp/$user/confirms" \
		bash -c "cd ~ && $*" </dev/tty
}

# answers <user> <confirm answers...> -- <menu choices...> saves the answers for gum.
# They go in a folder that the user owns.
# The fake gum replaces the files as it reads them, and it cannot do that to root's files in /tmp.
answers() {
	local user=$1 confirms=()
	shift
	mkdir -p "/tmp/$user"
	while (($#)) && [[ $1 != -- ]]; do
		confirms+=("$1")
		shift
	done
	shift
	printf '%s\n' "${confirms[@]}" >"/tmp/$user/confirms"
	printf '%s\n' "$@" >"/tmp/$user/choices"
	: >"/tmp/$user/gum.log"
	chown -R "$user:" "/tmp/$user"
}

# The fake gum answers choose and confirm from the lists above.
# It fills in input and logs each call.
mkdir -p "$stubs"
install -m 755 /src/tests/gum.sh "$stubs/gum"
# A real ssh-keygen would wait for a passphrase.
# The test checks the real ssh from openssh-client below.
install -m 755 /src/tests/ssh-keygen.sh "$stubs/ssh-keygen"

# The code under test is the commit checked out in /src, and install.sh downloads it.
# git is not installed yet, so the script writes the safe.directory setting by hand.
cp -a /src /srv/envsetup
printf '[safe]\n\tdirectory = *\n' >>/etc/gitconfig
# ENVSETUP_VERSION pins the version, or install.sh would check out the newest release.
# The version is the branch checked out in /src, or its commit if HEAD is detached.
read -r version </srv/envsetup/.git/HEAD
version=${version#ref: refs/heads/}
install="ENVSETUP_VERSION=${version@Q} ENVSETUP_REPO_URL=/srv/envsetup bash /srv/envsetup/install.sh"

echo "== $slug ($pm)"

# --- install.sh on a box without git --------------------------------------------------
mkuser beta
if command -v git >/dev/null; then
	result bootstrap WARN "git was already in the image, so install.sh's git hint wasn't exercised"
else
	# The user runs the command from the hint.
	# yes answers the package manager's questions.
	# The hint can hold two commands (apt-get update && apt-get install), so yes feeds the whole group.
	as beta "$install" >"$out/no-git.log" 2>&1
	hint=$(sed -n 's/^  \(.*git\)$/\1/p' "$out/no-git.log")
	# zypper ignores answers from a pipe, so it gets its flag for no questions.
	if [[ "$pm" == zypper ]]; then hint=${hint/zypper/zypper -n}; fi
	if [[ "$hint" == "sudo "* ]] && as beta "{ $hint; } < <(yes)" >>"$out/no-git.log" 2>&1 && command -v git >/dev/null; then
		result bootstrap PASS "install.sh showed '$hint', and that command installed git"
	else
		result bootstrap FAIL "the git hint failed: $(tail -n 3 "$out/no-git.log")"
	fi
fi
# deleted <log> passes when the download that install.sh names in its log is gone.
deleted() {
	local dl
	dl=$(sed -n 's/^Downloaded envsetup .* to \(.*\)\. envsetup deletes .*/\1/p' "$1")
	[[ -n "$dl" && ! -e "$dl" ]]
}
if as beta "$install --help" >"$out/bootstrap.log" 2>&1 &&
	grep -q '^Usage: ' "$out/bootstrap.log" && deleted "$out/bootstrap.log"; then
	result bootstrap PASS "install.sh ran setup.sh --help from a download, and deleted it"
else
	result bootstrap FAIL "install.sh failed: $(tail -n 3 "$out/bootstrap.log")"
fi

# --- gum: the menu cannot start without it -------------------------------------------
# as() starts from a clean environment, so pass ENVSETUP_ROOT.
# envsetup reads gum's pinned version from the code.
if as beta "PATH=\${PATH#$stubs:}; export ENVSETUP_ROOT=/srv/envsetup; source /srv/envsetup/lib/common.sh && envsetup::ensure_gum && command -v gum" >"$out/gum.log" 2>&1; then
	result gum PASS "installed: $(tail -n 1 "$out/gum.log")"
else
	result gum FAIL "envsetup::ensure_gum couldn't install gum: $(tail -n 2 "$out/gum.log")"
fi

# --- each profile: Run everything, then check what a new shell gets -----------------
# These are the commands that each profile's packages and installers should put on PATH.
common_cmds="git tmux vim curl wget htop tree unzip jq fzf rg column bat|batcat ssh"
declare -A expect=(
	[home]="$common_cmds python3 pip3 node npm nvim direnv shellcheck tig ncdu docker zsh"
	["work-full"]="$common_cmds nmap tcpdump strace lsof iostat mtr iotop iftop netstat rsync dig kubectl helm gh terraform aws"
	["work-lite"]=""
)
# The README's distro table documents these gaps.
# The test skips them the way the README tells users to.
# It reports them as WARN, not FAIL.
# The first list holds the packages, and the second holds the commands that they provide.
known_pkgs='' known_cmds=''
# On Alma and Rocky 9, the home run must answer the EPEL question with yes.
# Without EPEL, many listed packages fail to install.
epel=()
# shellcheck disable=SC1091 # this is the container's own os-release, not a file in this repo
case $(. /etc/os-release && echo "${ID-}:${VERSION_ID-}") in
almalinux:9.* | rocky:9.*) known_pkgs=direnv known_cmds=direnv epel=(yes) ;;
# Leap 16.0 does not package nmap, which only work lists.
opensuse-leap:16.*) known_pkgs=nmap known_cmds=nmap ;;
amzn:2023)
	known_pkgs="fzf ripgrep bat neovim direnv shellcheck ncdu"
	known_cmds="fzf rg bat|batcat nvim direnv shellcheck ncdu"
	;;
esac

for run in home work-full work-lite; do
	user=t-$run log=$out/$run.log
	mkuser "$user"
	mkdir -p "/home/$user/.config/envsetup"
	{
		[[ $run == home ]] && echo 'ENVSETUP_XDG_NINJA=1'
		[[ -n "${DISTROS_SKIP:-}$known_pkgs" ]] && echo "ENVSETUP_SKIP=(${DISTROS_SKIP:-} $known_pkgs)"
	} >"/home/$user/.config/envsetup/config.sh"
	chown -R "$user:" "/home/$user/.config"

	case $run in
	# The home answers, in order:
	# "no" answers the chsh question of "Set up zsh".
	# chsh would ask for a password.
	# On Alma and Rocky 9, "yes" turns on EPEL in "Install packages".
	# The next "no" turns down SSH signing.
	# Then "yes" moves dotfiles, if there are any to move.
	# work-full asks about EPEL again, and no answer declines.
	# EPEL stays on, because home runs first and installs epel-release in this container.
	home) answers "$user" no "${epel[@]}" no yes -- "Select profile" home "Set up zsh + oh-my-zsh" "Run everything" Quit ;;
	work-full) answers "$user" -- "Select profile" work full "Run everything" Quit ;;
	work-lite) answers "$user" -- "Select profile" work lite "Run everything" Quit ;;
	esac
	start=$SECONDS rc=0
	as "$user" "timeout ${DISTROS_RUN_TIMEOUT:-1200} env $install" >"$log" 2>&1 || rc=$?
	deleted "$log" || result "$run: download" FAIL "install.sh left its download behind"
	if ((rc == 0)); then
		result "$run" PASS "Run everything finished in $((SECONDS - start))s"
	elif ((rc == 124)); then
		result "$run" FAIL "timed out after $((SECONDS - start))s, probably waiting on a prompt: $(tail -n 2 "$log")"
	else
		result "$run" FAIL "setup.sh exited $rc after $((SECONDS - start))s: $(tail -n 2 "$log")"
	fi
	if grep -q "Couldn't install:" "$log"; then
		result "$run: packages" FAIL "$(grep -h "Couldn't install:" "$log")"
	fi
	if grep -q "Installers failed:" "$log"; then
		result "$run: installers" FAIL "$(grep -h "Installers failed:" "$log")"
	fi
	if grep -q "didn't finish" "/tmp/$user/gum.log"; then
		result "$run: steps" FAIL "$(grep -c "didn't finish" "/tmp/$user/gum.log") step(s) didn't finish; see $run.log"
	fi

	missing=() gaps=()
	for cmd in ${expect[$run]}; do
		if [[ " $known_cmds " == *" $cmd "* ]]; then
			gaps+=("$cmd")
			continue
		fi
		as "$user" "for c in ${cmd//|/ }; do command -v \$c && exit 0; done; exit 1" >/dev/null 2>&1 || missing+=("$cmd")
	done
	if ((${#missing[@]})); then
		result "$run: commands" FAIL "missing: ${missing[*]}"
	elif [[ -n "${expect[$run]}" ]]; then
		result "$run: commands" PASS "all $(($(wc -w <<<"${expect[$run]}") - ${#gaps[@]})) expected commands present"
	fi
	if ((${#gaps[@]})); then
		result "$run: commands" WARN "not packaged on this distro (see README), so skipped: ${gaps[*]}"
	fi

	shells=(bash)
	[[ $run == home ]] && shells+=(zsh)
	for sh in "${shells[@]}"; do
		if ! as "$user" "command -v $sh" >/dev/null 2>&1; then
			result "$run: $sh" FAIL "$sh isn't installed"
			continue
		fi
		as "$user" "setsid $sh -i -c 'alias ll' </dev/null" >"$out/$run.$sh.out" 2>"$out/$run.$sh.err"
		grep -vE 'job control|terminal process group|pgrp|cannot set terminal' "$out/$run.$sh.err" >"$out/$run.$sh.err.real" || true
		if [[ -s "$out/$run.$sh.err.real" ]]; then
			result "$run: $sh" FAIL "errors starting $sh: $(head -n 2 "$out/$run.$sh.err.real")"
		elif grep -q 'ls -alh' "$out/$run.$sh.out"; then
			result "$run: $sh" PASS "starts cleanly and loads the aliases"
		else
			result "$run: $sh" FAIL "starts, but without envsetup's aliases"
		fi
	done

	# The answers: remove, yes; keep config.sh, yes.
	answers "$user" yes yes --
	if as "$user" "$install --uninstall" >"$out/$run.uninstall.log" 2>&1 &&
		! grep -qs '# >>> envsetup >>>' "/home/$user/.bashrc" "/home/$user/.zshrc" &&
		[[ ! -e "/home/$user/.local/share/envsetup" ]]; then
		result "$run: uninstall" PASS "rc files clean, copy of shell/ removed"
	else
		result "$run: uninstall" FAIL "$(tail -n 2 "$out/$run.uninstall.log")"
	fi
done
