#!/usr/bin/env bash
# Entry point: gum-driven menu to link shell config and install packages.
set -euo pipefail

ENVSETUP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ENVSETUP_ROOT
source "$ENVSETUP_ROOT/lib/common.sh"
source "$ENVSETUP_ROOT/lib/config.sh"
source "$ENVSETUP_ROOT/lib/zsh.sh"
source "$ENVSETUP_ROOT/lib/installers.sh"
source "$ENVSETUP_ROOT/lib/git.sh"
source "$ENVSETUP_ROOT/lib/uninstall.sh"

CONFIG_DIR="$HOME/.config/envsetup"
PROFILE_FILE="$CONFIG_DIR/profile"
MODE_FILE="$CONFIG_DIR/mode"
RC_MARKER_BEGIN="# >>> envsetup >>>"
RC_MARKER_END="# <<< envsetup <<<"

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
	DRY_RUN_DIR=$(mktemp -d)
	trap 'rm -rf "$DRY_RUN_DIR"' EXIT
	cp -r "$CONFIG_DIR/." "$DRY_RUN_DIR/" 2>/dev/null || true
	CONFIG_DIR=$DRY_RUN_DIR
	PROFILE_FILE=$CONFIG_DIR/profile
	MODE_FILE=$CONFIG_DIR/mode
	ENVSETUP_USER_CONFIG=$CONFIG_DIR/config.sh
fi

if envsetup::dry_run && ! envsetup::has_cmd gum; then
	reply=
	read -rp "The dry run's menu needs gum, which isn't installed. Install it? That's the only change a dry run makes. [y/N] " reply || true
	[[ "$reply" == [yY]* ]] || exit 1
fi
envsetup::ensure_gum || exit 1

envsetup::current_profile() {
	if [[ -f "$PROFILE_FILE" ]]; then cat "$PROFILE_FILE"; fi
}

envsetup::set_profile() {
	mkdir -p "$CONFIG_DIR"
	echo "$1" >"$PROFILE_FILE"
}

# Mode only applies to the work profile: "lite" assumes no sudo access and
# skips package installs; "full" (the default) assumes sudo and does everything.
envsetup::current_mode() {
	[[ -f "$MODE_FILE" ]] && cat "$MODE_FILE" || echo full
}

envsetup::set_mode() {
	mkdir -p "$CONFIG_DIR"
	echo "$1" >"$MODE_FILE"
}

envsetup::clear_mode() {
	rm -f "$MODE_FILE"
}

envsetup::link_shell_config() {
	local rc_file
	if [[ "$ENVSETUP_SHELL" == zsh ]]; then
		envsetup::setup_zsh || return 1
		rc_file="$HOME/.zshrc"
	else
		rc_file="$HOME/.bashrc"
	fi

	if [[ -f "$rc_file" ]] && grep -qF "$RC_MARKER_BEGIN" "$rc_file"; then
		gum style --foreground 3 "Already linked in $rc_file"
		return 0
	fi
	if envsetup::dry_run; then
		envsetup::would "add a 4-line block to $rc_file that loads shell/ from $ENVSETUP_ROOT"
		return 0
	fi

	{
		echo "$RC_MARKER_BEGIN"
		echo "export ENVSETUP_ROOT=\"$ENVSETUP_ROOT\""
		# shellcheck disable=SC2016 # single-quoted on purpose: expands when the rc file sources it, not now
		echo '[ -f "$ENVSETUP_ROOT/shell/init.sh" ] && source "$ENVSETUP_ROOT/shell/init.sh"'
		echo "$RC_MARKER_END"
	} >>"$rc_file"

	gum style --foreground 2 "Linked shell config into $rc_file (restart your shell to pick it up)"
}

envsetup::install_packages_for_profile() {
	local profile=$1 manager
	if [[ "$profile" == work && "$(envsetup::current_mode)" == lite ]]; then
		gum style --foreground 3 "work (lite) assumes no sudo access, so package installs are skipped."
		return 0
	fi

	manager="$(envsetup::pkg_manager)"
	if [[ -z "$manager" ]]; then
		gum style --foreground 1 "No supported package manager found."
		return 1
	fi

	local pkgs=()
	readarray -t pkgs < <(envsetup::resolved_packages)

	if ((${#pkgs[@]} == 0)); then
		gum style --foreground 3 "No packages listed for $profile."
		return 0
	fi
	if envsetup::dry_run; then
		local how=$manager
		[[ "$manager" == brew ]] || how="sudo $manager"
		envsetup::would "install ${#pkgs[@]} packages with $how (ones already installed are left alone): ${pkgs[*]}"
		return 0
	fi

	gum style --bold --foreground 4 "Installing via $manager: ${pkgs[*]}"
	envsetup::install_packages "$manager" "${pkgs[@]}"
}

# Picker lines: "<value>  <what it does>". The summary comes from the same resolved
# config the actions use, so config.sh overrides show up in it. gum hands back the
# whole line and the caller keeps the first word, which works on any gum version.
envsetup::profile_label() {
	local profile=$1 summary list pkgs=() scripts=() names=() s
	envsetup::load_config "$profile" full >/dev/null 2>&1
	readarray -t pkgs < <(envsetup::resolved_packages)
	readarray -t scripts < <(envsetup::resolved_installers)
	for s in "${scripts[@]}"; do
		s=${s##*/}
		names+=("${s%.sh}")
	done
	if [[ "$ENVSETUP_SHELL" == zsh ]]; then summary="zsh + oh-my-zsh"; else summary=bash; fi
	summary+=" · ${#pkgs[@]} packages"
	if ((${#names[@]} > 0)); then
		printf -v list '%s, ' "${names[@]}"
		summary+=" · ${#names[@]} installer"
		((${#names[@]} == 1)) || summary+=s
		summary+=" (${list%, })"
	else
		summary+=" · no installers"
	fi
	printf '%s  %s\n' "$profile" "$summary"
}

envsetup::mode_labels() {
	local pkgs=() scripts=()
	envsetup::load_config work full >/dev/null 2>&1
	readarray -t pkgs < <(envsetup::resolved_packages)
	readarray -t scripts < <(envsetup::resolved_installers)
	echo "full  uses sudo: installs ${#pkgs[@]} packages and runs ${#scripts[@]} installers"
	echo "lite  no sudo: only the prompt, aliases and git config; installs nothing"
}

envsetup::welcome() {
	gum style --border normal --padding "0 1" \
		"Welcome to envsetup. Nothing changes until you pick an action." \
		"1. Select profile: what kind of machine this is (switch any time)." \
		"2. Preview everything shows what would change, without changing it." \
		"3. Run everything, or run the steps one at a time." \
		"Your own tweaks go in Edit config. More: ./setup.sh --help"
}

# Each step runs on its own, so one that fails (say, a package that can't be installed)
# doesn't stop the rest.
envsetup::run_everything() {
	envsetup::run_step envsetup::link_shell_config
	envsetup::run_step envsetup::setup_git
	envsetup::run_step envsetup::install_packages_for_profile "$1"
	envsetup::run_step envsetup::run_installers "$1"
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

envsetup::main_menu() {
	local profile mode label choice was result labels=()
	[[ -n "$(envsetup::current_profile)" ]] || envsetup::welcome
	while true; do
		profile="$(envsetup::current_profile)"
		label="${profile:-none}"
		[[ "$profile" == work ]] && label+=" ($(envsetup::current_mode))"
		envsetup::load_config "$profile" "$(envsetup::current_mode)"
		choice="$(gum choose \
			"Select profile (current: $label)" \
			"Edit config" \
			"Link shell config" \
			"Configure git" \
			"Install packages" \
			"Run installers" \
			"Preview everything" \
			"Run everything" \
			"Uninstall" \
			"Quit")" || break # esc/ctrl+c: gum exits non-zero with no selection

		case "$choice" in
		"Select profile"*)
			# Nothing is saved until both choices are made, so cancelling either is a no-op.
			gum style --foreground 4 "What kind of machine is this?"
			profile="$(gum choose "$(envsetup::profile_label work)" "$(envsetup::profile_label home)")" || continue
			profile=${profile%% *}
			if [[ "$profile" == work ]]; then
				gum style --foreground 4 "Do you have sudo on this machine?"
				readarray -t labels < <(envsetup::mode_labels)
				mode="$(gum choose "${labels[@]}")" || continue
				envsetup::set_mode "${mode%% *}"
			else
				envsetup::clear_mode
			fi
			envsetup::set_profile "$profile"
			;;
		"Edit config")
			envsetup::dry_run && gum style --foreground 6 "Dry run: editing a copy of your config; changes last until you quit."
			envsetup::run_step envsetup::edit_config
			;;
		"Link shell config")
			envsetup::run_step envsetup::link_shell_config
			;;
		"Configure git")
			envsetup::run_step envsetup::setup_git
			;;
		"Install packages")
			[[ -z "$profile" ]] && { gum style --foreground 1 "Select a profile first."; continue; }
			envsetup::run_step envsetup::install_packages_for_profile "$profile"
			;;
		"Run installers")
			[[ -z "$profile" ]] && { gum style --foreground 1 "Select a profile first."; continue; }
			envsetup::run_step envsetup::run_installers "$profile"
			;;
		"Preview everything")
			[[ -z "$profile" ]] && { gum style --foreground 1 "Select a profile first."; continue; }
			gum style --bold "What Run everything would do for $label (nothing is changed):"
			was=$ENVSETUP_DRY_RUN
			ENVSETUP_DRY_RUN=1
			envsetup::run_everything "$profile"
			ENVSETUP_DRY_RUN=$was
			;;
		"Run everything")
			[[ -z "$profile" ]] && { gum style --foreground 1 "Select a profile first."; continue; }
			envsetup::dry_run && gum style --bold "Dry run: what Run everything would do for $label:"
			envsetup::run_everything "$profile"
			;;
		"Uninstall")
			result=0
			envsetup::uninstall || result=$?
			# Done for real: nothing left for the menu to act on.
			[[ "$result" == 0 ]] && ! envsetup::dry_run && break
			;;
		"Quit" | "")
			break
			;;
		esac
	done
}

gum style --border rounded --padding "1 2" --bold "envsetup"
envsetup::dry_run && gum style --foreground 6 "Dry run: nothing is saved, installed or linked. Picks and config edits last until you quit."
if ((UNINSTALL)); then
	# Loaded so it knows which shell envsetup would have set up for your profile.
	envsetup::load_config "$(envsetup::current_profile)" "$(envsetup::current_mode)"
	result=0
	envsetup::uninstall || result=$?
	((result == 2)) && result=0 # backing out isn't an error
	exit "$result"
fi
envsetup::main_menu
