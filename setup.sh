#!/usr/bin/env bash
# Entry point: the gum menu that sets up this machine's shell, git, packages and tools.
set -euo pipefail

ENVSETUP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ENVSETUP_ROOT
source "$ENVSETUP_ROOT/lib/common.sh"
source "$ENVSETUP_ROOT/lib/config.sh"
source "$ENVSETUP_ROOT/lib/zsh.sh"
source "$ENVSETUP_ROOT/lib/installers.sh"
source "$ENVSETUP_ROOT/lib/git.sh"
source "$ENVSETUP_ROOT/lib/uninstall.sh"
source "$ENVSETUP_ROOT/lib/xdg.sh"

# Where the menu keeps its picks: the real state dir, or a throwaway copy in a dry run.
STATE_DIR=$ENVSETUP_STATE

envsetup::usage() {
	cat <<'EOF'
Usage: ./setup.sh [options]

Sets up this machine's shell (aliases, prompt), git, packages and tools, from an
interactive menu. Nothing changes until you pick an action in it.

Profiles (pick one from the menu; switch any time):
  home  zsh + oh-my-zsh, general-use and light-dev packages
  work  bash, SRE tools (kubectl, terraform, helm, ...), in one of two modes:
          full  uses sudo: installs packages and runs vendor installers
          lite  no sudo: only the prompt, aliases and git config; installs nothing

Your own changes go in ~/.config/envsetup/config.sh ("Edit config" in the menu,
template: config.example.sh), outside this repo, so updates never conflict.

To see what it would do first, use --dry-run, or "Preview everything" in the menu.
To take it all back out, use --uninstall, or "Uninstall" in the menu.

"Move dotfiles to XDG dirs" moves dotfiles out of $HOME into ~/.config, ~/.local and
~/.cache where that's safe to do automatically (from xdg-ninja's notes). Set
ENVSETUP_XDG_NINJA=1 in config.sh to make it part of "Run everything".

Options:
  -n, --dry-run    walk through the menu without changing anything: every step says
                   what it would do instead; profile picks and "Edit config" work
                   but only last until you quit
      --uninstall  remove what envsetup added (rc-file block, git include, saved
                   state), asking before anything that might be yours; packages
                   and tools stay. Combine with --dry-run to preview it
  -h, --help       show this help and exit
EOF
}

ENVSETUP_DRY_RUN=0
UNINSTALL=0
while (($#)); do
	case $1 in
	-h | --help)
		envsetup::usage
		exit 0
		;;
	-n | --dry-run) ENVSETUP_DRY_RUN=1 ;;
	--uninstall) UNINSTALL=1 ;;
	*)
		printf 'setup.sh: unknown option: %s\n\n' "$1" >&2
		envsetup::usage >&2
		exit 2
		;;
	esac
	shift
done

if envsetup::dry_run; then
	# Profile picks and config edits go to a throwaway copy, so the menu behaves as
	# usual for the session while ~/.config/envsetup stays untouched.
	STATE_DIR=$(mktemp -d)
	trap 'rm -rf "$STATE_DIR"' EXIT
	cp -r "$ENVSETUP_STATE/." "$STATE_DIR/" 2>/dev/null || true
	ENVSETUP_USER_CONFIG=$STATE_DIR/config.sh
	if ! envsetup::has_cmd gum; then
		reply=
		read -rp "The dry run's menu needs gum, which isn't installed. Install it? That's the only change a dry run makes. [y/N] " reply || true
		[[ "$reply" == [yY]* ]] || exit 1
	fi
fi
envsetup::ensure_gum || exit 1

# read_state <profile|mode> [default], save_state <profile|mode> <value> (empty deletes).
envsetup::read_state() {
	if [[ -f "$STATE_DIR/$1" ]]; then echo "$(<"$STATE_DIR/$1")"; else echo "${2:-}"; fi
}

envsetup::save_state() {
	mkdir -p "$STATE_DIR"
	if [[ -n "$2" ]]; then echo "$2" >"$STATE_DIR/$1"; else rm -f "$STATE_DIR/$1"; fi
}

envsetup::link_shell_config() {
	local rc_file="$HOME/.bashrc"
	if [[ "$ENVSETUP_SHELL" == zsh ]]; then
		envsetup::setup_zsh || return 1
		rc_file="$HOME/.zshrc"
	fi
	if [[ -f "$rc_file" ]] && grep -qF "$ENVSETUP_RC_BEGIN" "$rc_file"; then
		gum style --foreground 3 "Already linked in $rc_file"
		return 0
	fi
	if envsetup::dry_run; then
		envsetup::would "add a 4-line block to $rc_file that loads shell/ from $ENVSETUP_ROOT"
		return 0
	fi
	# shellcheck disable=SC2016 # the last line expands when the rc file runs, not now
	printf '%s\n' "$ENVSETUP_RC_BEGIN" "export ENVSETUP_ROOT=\"$ENVSETUP_ROOT\"" \
		'[ -f "$ENVSETUP_ROOT/shell/init.sh" ] && source "$ENVSETUP_ROOT/shell/init.sh"' \
		"$ENVSETUP_RC_END" >>"$rc_file"
	gum style --foreground 2 "Linked shell config into $rc_file (restart your shell to pick it up)"
}

envsetup::install_packages() {
	local manager pkg name pkgs=() names=()
	if envsetup::lite; then
		gum style --foreground 3 "work (lite) assumes no sudo access, so package installs are skipped."
		return 0
	fi
	manager="$(envsetup::pkg_manager)"
	if [[ -z "$manager" ]]; then
		gum style --foreground 1 "No supported package manager found."
		return 1
	fi
	readarray -t pkgs < <(envsetup::resolved_packages)
	for pkg in "${pkgs[@]}"; do
		name=$(envsetup::pkg_name "$manager" "$pkg")
		if [[ -n "$name" ]]; then names+=("$name"); fi
	done
	if ((${#names[@]} == 0)); then
		gum style --foreground 3 "No packages listed for $ENVSETUP_PROFILE."
		return 0
	fi
	if [[ "$manager" == dnf ]]; then envsetup::enable_epel; fi
	if envsetup::dry_run; then
		[[ "$manager" == brew || "$manager" == nix ]] || manager="sudo $manager"
		envsetup::would "install ${#names[@]} packages with $manager (ones already installed are left alone): ${names[*]}"
	else
		gum style --bold --foreground 4 "Installing via $manager: ${names[*]}"
		envsetup::pkg_install "$manager" "${pkgs[@]}"
	fi
}

# Picker lines are "<value>  <what it does>", worked out from the same resolved config
# the actions run on. gum hands back the whole line; callers keep the first word.
envsetup::profile_label() {
	local summary=bash list pkgs=() names=()
	envsetup::load_config "$1" full >/dev/null 2>&1
	readarray -t pkgs < <(envsetup::resolved_packages)
	readarray -t names < <(envsetup::resolved_installers)
	names=("${names[@]##*/}")
	names=("${names[@]%.sh}")
	[[ "$ENVSETUP_SHELL" == zsh ]] && summary="zsh + oh-my-zsh"
	summary+=" · ${#pkgs[@]} packages · "
	if ((${#names[@]} == 0)); then
		summary+="no installers"
	else
		printf -v list '%s, ' "${names[@]}"
		summary+="${#names[@]} installer"
		((${#names[@]} == 1)) || summary+=s
		summary+=" (${list%, })"
	fi
	printf '%s  %s\n' "$1" "$summary"
}

envsetup::mode_labels() {
	local pkgs=() scripts=()
	envsetup::load_config work full >/dev/null 2>&1
	readarray -t pkgs < <(envsetup::resolved_packages)
	readarray -t scripts < <(envsetup::resolved_installers)
	echo "full  uses sudo: installs ${#pkgs[@]} packages and runs ${#scripts[@]} installers"
	echo "lite  no sudo: only the prompt, aliases and git config; installs nothing"
}

envsetup::pick_profile() {
	local profile mode="" labels=()
	# Nothing is saved until both choices are made, so cancelling either is a no-op.
	gum style --foreground 4 "What kind of machine is this?"
	profile="$(gum choose "$(envsetup::profile_label work)" "$(envsetup::profile_label home)")" || return 0
	if [[ "${profile%% *}" == work ]]; then
		gum style --foreground 4 "Do you have sudo on this machine?"
		readarray -t labels < <(envsetup::mode_labels)
		mode="$(gum choose "${labels[@]}")" || return 0
	fi
	envsetup::save_state mode "${mode%% *}"
	envsetup::save_state profile "${profile%% *}"
}

# Runs a menu action with set -e still in force (a bare `action || ...` would switch it
# off inside the action), but a failure returns to the menu instead of ending setup.
envsetup::run_step() {
	local rc
	set +e
	(
		set -e
		"$@"
	)
	rc=$?
	set -e
	((rc == 0)) || gum style --foreground 1 "That step didn't finish; see above. Fix it and run it again."
}

# Each step runs on its own, so one that fails (say, a package that can't be installed)
# doesn't stop the rest.
envsetup::run_everything() {
	local step
	for step in link_shell_config configure_git install_packages run_installers; do
		envsetup::run_step "envsetup::$step"
	done
	if [[ "$ENVSETUP_XDG_NINJA" == 1 ]]; then envsetup::run_step envsetup::xdg_tidy; fi
}

envsetup::main_menu() {
	local profile label choice
	[[ -n "$(envsetup::read_state profile)" ]] || gum style --border normal --padding "0 1" \
		"Welcome to envsetup. Nothing changes until you pick an action." \
		"1. Select profile: what kind of machine this is (switch any time)." \
		"2. Preview everything shows what would change, without changing it." \
		"3. Run everything, or run the steps one at a time." \
		"Your own tweaks go in Edit config. More: ./setup.sh --help"
	while true; do
		profile="$(envsetup::read_state profile)"
		envsetup::load_config "$profile" "$(envsetup::read_state mode full)"
		label="${profile:-none}"
		[[ "$profile" == work ]] && label+=" ($ENVSETUP_MODE)"
		choice="$(gum choose "Select profile (current: $label)" "Edit config" "Link shell config" \
			"Configure git" "Install packages" "Run installers" "Move dotfiles to XDG dirs" \
			"Preview everything" "Run everything" "Uninstall" "Quit")" || break # esc/ctrl+c

		case "$choice" in
		"Install packages" | "Run installers" | *everything)
			if [[ -z "$profile" ]]; then
				gum style --foreground 1 "Select a profile first."
				continue
			fi
			;;
		esac
		case "$choice" in
		"Select profile"*) envsetup::run_step envsetup::pick_profile ;;
		"Edit config")
			envsetup::dry_run && gum style --foreground 6 "Dry run: editing a copy of your config; changes last until you quit."
			envsetup::run_step envsetup::edit_config
			;;
		"Link shell config") envsetup::run_step envsetup::link_shell_config ;;
		"Configure git") envsetup::run_step envsetup::configure_git ;;
		"Install packages") envsetup::run_step envsetup::install_packages ;;
		"Run installers") envsetup::run_step envsetup::run_installers ;;
		"Move dotfiles to XDG dirs") envsetup::run_step envsetup::xdg_tidy ;;
		"Preview everything")
			gum style --bold "What Run everything would do for $label (nothing is changed):"
			ENVSETUP_DRY_RUN=1 envsetup::run_everything
			;;
		"Run everything")
			envsetup::dry_run && gum style --bold "Dry run: what Run everything would do for $label:"
			envsetup::run_everything
			;;
		"Uninstall")
			# Once it's really gone there's nothing left for the menu to act on.
			if envsetup::uninstall && ! envsetup::dry_run; then break; fi
			;;
		*) break ;;
		esac
	done
}

gum style --border rounded --padding "1 2" --bold "envsetup"
envsetup::dry_run && gum style --foreground 6 "Dry run: nothing is saved, installed or linked. Picks and config edits last until you quit."
if ((UNINSTALL)); then
	# Loaded so it knows which shell envsetup would have set up for your profile.
	envsetup::load_config "$(envsetup::read_state profile)" "$(envsetup::read_state mode full)"
	envsetup::uninstall || (($? == 2)) # backing out isn't an error
	exit 0
fi
envsetup::main_menu
