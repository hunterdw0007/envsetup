#!/usr/bin/env bash
# Runs as root inside one distro container, after inside.sh. Uses envsetup the way a
# beta tester would, as non-root users with sudo, with real package installs and
# downloads. Only gum's UI is scripted, so the menu can run unattended. Every phase
# writes a line to /report/<slug>/summary.tsv; logs go next to it.
set -uo pipefail # no -e: each phase reports its own outcome and the next one still runs

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

# A non-root user with passwordless sudo that keeps the hook's env (proxy, CA).
mkuser() {
	useradd -m -s /bin/bash "$1"
	printf '%s ALL=(ALL) NOPASSWD: ALL\nDefaults env_keep += "DEBIAN_FRONTEND %s"\n' "$1" "${DISTROS_KEEP_ENV:-}" >"/etc/sudoers.d/$1"
	chmod 0440 "/etc/sudoers.d/$1"
}

# as <user> <command>: runs it in a login-like bash for that user, on the terminal
# (install.sh and setup.sh read answers from /dev/tty).
as() {
	local user=$1
	shift
	# shellcheck disable=SC2024 # root opening /dev/tty for the user's process is the point
	sudo -u "$user" -H env "PATH=$stubs:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
		"SMOKE_LOG=/tmp/$user/gum.log" "SMOKE_CHOICES=/tmp/$user/choices" "SMOKE_CONFIRMS=/tmp/$user/confirms" \
		bash -c "cd ~ && $*" </dev/tty
}

# answers <user> <confirm answers...> -- <menu choices...>. Kept in a directory the
# user owns: the stub edits them with sed -i, which can't replace root's files in /tmp.
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

# gum stand-in: answers choose/confirm from the queues above, fills input, logs calls.
mkdir -p "$stubs"
cat >"$stubs/gum" <<'GUM'
#!/usr/bin/env bash
echo "gum $*" >>"$SMOKE_LOG"
case $1 in
choose)
	answer=ESC
	read -r answer <"$SMOKE_CHOICES" || true
	sed -i 1d "$SMOKE_CHOICES"
	[[ $answer == ESC ]] && exit 1
	echo "$answer" ;;
confirm)
	answer=no
	read -r answer <"$SMOKE_CONFIRMS" || true
	sed -i 1d "$SMOKE_CONFIRMS"
	[[ $answer == yes ]] ;;
input) [[ $* == *@* ]] && echo beta@example.com || echo "Beta Tester" ;;
style) echo "${*: -1}" ;;
esac
GUM
chmod 755 "$stubs/gum"

# The code under test: the commit checked out in /src, cloned the way install.sh does.
# No git yet, so the safe.directory exception is written by hand.
cp -a /src /srv/envsetup
printf '[safe]\n\tdirectory = *\n' >>/etc/gitconfig

echo "== $slug ($pm)"

# --- install.sh on a box without git --------------------------------------------------
mkuser beta
if command -v git >/dev/null; then
	result bootstrap WARN "git was already in the image, so install.sh's git install wasn't exercised"
fi
if as beta "ENVSETUP_REPO_URL=/srv/envsetup ENVSETUP_DIR=\$HOME/envsetup bash /srv/envsetup/install.sh --help" >"$out/bootstrap.log" 2>&1 &&
	[[ -x /home/beta/envsetup/setup.sh ]]; then
	result bootstrap PASS "install.sh installed git, cloned and ran setup.sh --help"
else
	result bootstrap FAIL "install.sh failed: $(tail -n 3 "$out/bootstrap.log")"
fi

# --- gum: the menu can't start without it ---------------------------------------------
if as beta "PATH=\${PATH#$stubs:}; source envsetup/lib/common.sh && envsetup::ensure_gum && command -v gum" >"$out/gum.log" 2>&1; then
	result gum PASS "installed: $(tail -n 1 "$out/gum.log")"
else
	result gum FAIL "envsetup::ensure_gum couldn't install gum: $(tail -n 2 "$out/gum.log")"
fi

# --- each profile: Run everything, then check what a new shell gets -----------------
# Commands each profile's packages and installers should leave on PATH.
common_cmds="git tmux vim curl wget htop tree unzip jq fzf rg column bat|batcat"
declare -A expect=(
	[home]="$common_cmds python3 pip3 node npm nvim direnv shellcheck tig ncdu docker zsh"
	[work-full]="$common_cmds nmap tcpdump strace lsof iostat mtr iotop iftop netstat rsync dig kubectl helm gh terraform aws"
	[work-lite]=""
)

for run in home work-full work-lite; do
	user=t-$run log=$out/$run.log
	mkuser "$user"
	as "$user" "ENVSETUP_REPO_URL=/srv/envsetup ENVSETUP_DIR=\$HOME/envsetup bash /srv/envsetup/install.sh --help" >/dev/null 2>&1
	mkdir -p "/home/$user/.config/envsetup"
	{
		[[ $run == home ]] && echo 'ENVSETUP_XDG_NINJA=1'
		[[ -n "${DISTROS_SKIP:-}" ]] && echo "ENVSETUP_SKIP=($DISTROS_SKIP)"
	} >"/home/$user/.config/envsetup/config.sh"
	chown -R "$user:" "/home/$user/.config"

	case $run in
	# zsh first, so "no" always lands on its chsh question (chsh would ask for a password);
	# "yes" then moves dotfiles, if there are any to move.
	home) answers "$user" no yes -- "Select profile" home "Set up zsh + oh-my-zsh" "Run everything" Quit ;;
	work-full) answers "$user" -- "Select profile" work full "Run everything" Quit ;;
	work-lite) answers "$user" -- "Select profile" work lite "Run everything" Quit ;;
	esac
	start=$SECONDS rc=0
	as "$user" "timeout ${DISTROS_RUN_TIMEOUT:-1200} envsetup/setup.sh" >"$log" 2>&1 || rc=$?
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

	missing=()
	for cmd in ${expect[$run]}; do
		as "$user" "for c in ${cmd//|/ }; do command -v \$c && exit 0; done; exit 1" >/dev/null 2>&1 || missing+=("$cmd")
	done
	if ((${#missing[@]})); then
		result "$run: commands" FAIL "missing: ${missing[*]}"
	elif [[ -n "${expect[$run]}" ]]; then
		result "$run: commands" PASS "all $(wc -w <<<"${expect[$run]}") expected commands present"
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

	# Remove? yes; keep config.sh? yes.
	answers "$user" yes yes --
	if as "$user" "envsetup/setup.sh --uninstall" >"$out/$run.uninstall.log" 2>&1 &&
		! grep -qs '# >>> envsetup >>>' "/home/$user/.bashrc" "/home/$user/.zshrc"; then
		result "$run: uninstall" PASS "rc files clean"
	else
		result "$run: uninstall" FAIL "$(tail -n 2 "$out/$run.uninstall.log")"
	fi
done
