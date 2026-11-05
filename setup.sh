#!/usr/bin/env bash
# setup.sh opens the gum menu.
# The menu sets up this machine's shell, git, packages and tools.
set -euo pipefail

# This check runs first, so the old bash 3.2 on a Mac can parse it.
# A clone on a Mac stops here.
if [[ "$OSTYPE" != linux* ]]; then
	printf '%s\n' "envsetup supports Linux only." "v0.3.0 is the last release that supports macOS." \
		"To install v0.3.0, run: git fetch --tags && git checkout v0.3.0 && ./setup.sh" \
		"To uninstall envsetup, run: git fetch --tags && git checkout v0.3.0 && ./setup.sh --uninstall" >&2
	exit 1
fi

ENVSETUP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ENVSETUP_ROOT
source "$ENVSETUP_ROOT/lib/common.sh"
source "$ENVSETUP_ROOT/lib/config.sh"
source "$ENVSETUP_ROOT/lib/zsh.sh"
source "$ENVSETUP_ROOT/lib/installers.sh"
source "$ENVSETUP_ROOT/lib/git.sh"
source "$ENVSETUP_ROOT/lib/uninstall.sh"
source "$ENVSETUP_ROOT/lib/xdg.sh"

# The menu saves its choices here.
# A dry run uses a temporary copy instead.
STATE_DIR=$ENVSETUP_STATE

envsetup::usage() {
	cat <<'EOF'
Usage: ./setup.sh [options]

setup.sh sets up this machine's shell, git, packages and tools.
You choose what it does from a menu.
Nothing changes until you select an action.

Profiles (select one in the menu, and change it at any time):
  home  bash, with packages for general use and light development
  work  bash, with tools for operations work (kubectl, terraform, helm, ...)
        The work profile has two modes:
          full  uses sudo: installs packages and runs installers
          lite  no sudo: only the prompt, aliases and git config; installs nothing

Put your own changes in ~/.config/envsetup/config.sh.
If you set XDG_CONFIG_HOME, the file is $XDG_CONFIG_HOME/envsetup/config.sh.
"Edit config" in the menu creates the file from config.example.sh.
The file is outside this repo, so updates never change it.

To see the changes first, use --dry-run, or "Preview everything" in the menu.
To remove what envsetup added, use --uninstall, or "Uninstall" in the menu.
To update, run the curl command from the README again.
That command downloads the newest release into a temporary folder.
To get another release, set ENVSETUP_VERSION (for example ENVSETUP_VERSION=v0.2.0).
The command runs this menu from that folder and deletes the folder afterwards.

"Link shell config" copies shell/ to ~/.local/share/envsetup.
If you set XDG_DATA_HOME, it copies shell/ to $XDG_DATA_HOME/envsetup.
New shells load that copy.
The action links ~/.bashrc to the copy.
It also links ~/.zshrc if zsh is your login shell.

"Set up zsh + oh-my-zsh" installs zsh and oh-my-zsh if they are missing.
It offers to make zsh your login shell.
It links the same config into ~/.zshrc.
To add it to "Run everything", set ENVSETUP_SHELL=zsh in config.sh.

"Move dotfiles to XDG dirs" moves dotfiles out of $HOME into ~/.config, ~/.local and ~/.cache.
It moves a dotfile only when xdg-ninja's notes show that the move is safe.
To add it to "Run everything", set ENVSETUP_XDG_NINJA=1 in config.sh.

Options:
  -n, --dry-run    open the menu, but change nothing; each action says what it
                   would do instead; profile choices and "Edit config" last
                   only until you quit
      --uninstall  remove what envsetup added: the startup file block, the copy
                   of the shell config, the git include and the saved choices;
                   ask before removing anything that may be yours; keep packages
                   and tools; add --dry-run to see the changes first
      --version    show the release and exit
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
	--version)
		envsetup::version
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

# This run's temporary folder.
# Installers run in their own processes and share it.
ENVSETUP_TMP=$(mktemp -d)
export ENVSETUP_TMP
trap 'rm -rf "$ENVSETUP_TMP"' EXIT

if envsetup::dry_run; then
	# Profile choices and config edits go to a temporary copy.
	# So the menu works as usual, and ~/.config/envsetup does not change.
	STATE_DIR=$ENVSETUP_TMP/state
	mkdir "$STATE_DIR"
	cp -r "$ENVSETUP_STATE/." "$STATE_DIR/" 2>/dev/null || true
	ENVSETUP_USER_CONFIG=$STATE_DIR/config.sh
	if ! envsetup::has_cmd gum; then
		reply=
		read -rp "The menu needs gum, and gum is not installed. Install gum? The dry run makes no other change. [y/N] " reply || true
		[[ "$reply" == [yY]* ]] || exit 1
	fi
fi
envsetup::ensure_gum || exit 1

# read_state <profile|mode> [default] prints a saved choice.
# save_state <profile|mode> <value> saves a choice.
# An empty value deletes the choice.
envsetup::read_state() {
	if [[ -f "$STATE_DIR/$1" ]]; then echo "$(<"$STATE_DIR/$1")"; else echo "${2:-}"; fi
}

envsetup::save_state() {
	mkdir -p "$STATE_DIR"
	if [[ -n "$2" ]]; then echo "$2" >"$STATE_DIR/$1"; else rm -f "$STATE_DIR/$1"; fi
}

# copy_shell copies shell/ to ENVSETUP_DATA and records the release.
# New shells load that copy, not this checkout, because install.sh deletes its download.
# Each run replaces the copy.
# A new release updates the copy, and the same release leaves it the same.
envsetup::copy_shell() {
	local version
	version=$(envsetup::version)
	if envsetup::dry_run; then
		envsetup::would "copy shell/ ($version) to $ENVSETUP_DATA, which new shells load"
		return 0
	fi
	mkdir -p "$ENVSETUP_DATA"
	rm -rf "$ENVSETUP_DATA/shell"
	cp -R "$ENVSETUP_ROOT/shell" "$ENVSETUP_DATA/"
	echo "$version" >"$ENVSETUP_DATA/version"
	gum style --foreground 2 "Copied shell config ($version) to $ENVSETUP_DATA"
}

# link_rc <file> adds the block that loads the copy of shell/init.sh.
# It adds the block only once.
# Older releases loaded shell/ from a checkout (~/envsetup).
# link_rc rewrites such an old block in place.
envsetup::link_rc() {
	# The block sets ENVSETUP_STATE, so every shell uses the folder that setup used (see shell/state.sh).
	# %q quotes the two paths.
	# So a space, ", $ or ` in a path does not break the startup file.
	# And the startup file does not run any part of a path as a command.
	# bash and zsh both read the output of %q.
	local root state block old
	printf -v root 'export ENVSETUP_ROOT=%q' "$ENVSETUP_DATA"
	printf -v state 'export ENVSETUP_STATE=%q ENVSETUP_STATE_HOME=%q' "$ENVSETUP_STATE" "$HOME"
	# shellcheck disable=SC2016 # the fourth line expands when the startup file runs, not now
	printf -v block '%s\n' "$ENVSETUP_RC_BEGIN" "$root" "$state" \
		'[ -f "$ENVSETUP_ROOT/shell/init.sh" ] && source "$ENVSETUP_ROOT/shell/init.sh"' \
		"$ENVSETUP_RC_END"
	if [[ -f "$1" ]] && grep -qF "$ENVSETUP_RC_BEGIN" "$1"; then
		if grep -qxF "$root" "$1"; then
			gum style --foreground 3 "Already linked in $1"
			return 0
		fi
		# Find the checkout that the old block loaded.
		# Running the block's own export line undoes the quotes from %q.
		old=$(bash -c "$(grep -m 1 '^export ENVSETUP_ROOT=' "$1")"'; printf %s "$ENVSETUP_ROOT"' 2>/dev/null) || old=
		if envsetup::dry_run; then
			envsetup::would "rewrite the envsetup block in $1 to load shell/ from $ENVSETUP_DATA"
		else
			envsetup::remove_rc_block "$1" "$block"
			gum style --foreground 2 "Rewrote the envsetup block in $1 to load shell/ from $ENVSETUP_DATA"
		fi
		envsetup::drop_checkout "$old"
		return 0
	fi
	if envsetup::dry_run; then
		envsetup::would "add a 5-line block to $1 that loads shell/ from $ENVSETUP_DATA"
		return 0
	fi
	printf '%s' "$block" >>"$1"
	gum style --foreground 2 "Linked shell config into $1. Open a new shell to load it."
}

# drop_checkout <dir> offers to delete the checkout that an old block loaded shell/ from.
# Nothing needs that checkout any more.
# It asks only once in each run.
# The default answer keeps the checkout.
envsetup::drop_checkout() {
	if [[ ! -f "$1/shell/init.sh" || "$1" == "$ENVSETUP_DATA" || "$1" == "${ENVSETUP_ASKED:-}" ]]; then return 0; fi
	ENVSETUP_ASKED=$1
	if [[ "$1" == "$ENVSETUP_ROOT" ]]; then
		gum style "New shells no longer load $1. You can delete it after setup ends. Keep it if you work on envsetup there."
	elif gum confirm "Keep $1? New shells and updates no longer use it."; then
		return 0
	elif envsetup::dry_run; then
		envsetup::would "delete $1"
	else
		rm -rf "$1"
		gum style --foreground 2 "Deleted $1"
	fi
}

# link_shell_config always links ~/.bashrc, so every bash gets the config.
# It also links your login shell's startup file, so new terminals get the config.
# It sets up zsh + oh-my-zsh only if you opt in.
# To opt in, set ENVSETUP_SHELL=zsh or use the menu action.
envsetup::link_shell_config() {
	envsetup::copy_shell
	envsetup::link_rc "$HOME/.bashrc"
	if [[ "${SHELL##*/}" == zsh ]]; then envsetup::link_rc "$HOME/.zshrc"; fi
	if [[ "$ENVSETUP_SHELL" == zsh ]]; then
		envsetup::install_zsh
		envsetup::link_rc "$HOME/.zshrc"
	fi
}

envsetup::set_up_zsh() {
	envsetup::install_zsh
	envsetup::copy_shell
	envsetup::link_rc "$HOME/.zshrc"
}

envsetup::install_packages() {
	local manager pkg name pkgs=() names=()
	if envsetup::lite; then
		gum style --foreground 3 "work (lite) does not assume sudo, so it installs no packages."
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
		[[ "$manager" == brew || "$manager" == nix ]] || manager+=" (as root)"
		envsetup::would "install ${#names[@]} packages with $manager, and skip the ones already installed: ${names[*]}"
	else
		gum style --bold --foreground 4 "Installing with $manager: ${names[*]}"
		envsetup::pkg_install "$manager" "${pkgs[@]}"
	fi
}

# Picker lines are "<value>  <what it does>".
# The description comes from the same resolved config that the actions use.
# gum returns the whole line, and callers keep the first word.
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
	# pick_profile saves nothing until you make both choices.
	# So cancelling either choice changes nothing.
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

# run_step runs a menu action with set -e still on.
# A bare `action || ...` would turn off set -e inside the action.
# A failure returns to the menu and does not end setup.
envsetup::run_step() {
	local rc
	set +e
	(
		set -e
		"$@"
	)
	rc=$?
	set -e
	((rc == 0)) || gum style --foreground 1 "That step didn't finish. The error is above. Fix it and run the step again."
}

# Each step runs on its own.
# So a failed step does not stop the other steps.
# A package that fails to install is an example.
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
		"Welcome to envsetup. Nothing changes until you select an action." \
		"1. Select profile tells envsetup what kind of machine this is. You can change it at any time." \
		"2. Preview everything shows the changes. It does not make them." \
		"3. Run everything, or run the steps one at a time." \
		"Put your own changes in Edit config. For more, run ./setup.sh --help"
	while true; do
		profile="$(envsetup::read_state profile)"
		envsetup::load_config "$profile" "$(envsetup::read_state mode full)"
		label="${profile:-none}"
		[[ "$profile" == work ]] && label+=" ($ENVSETUP_MODE)"
		choice="$(gum choose "Select profile (current: $label)" "Edit config" "Link shell config" \
			"Set up zsh + oh-my-zsh" "Configure git" "Install packages" "Run installers" \
			"Move dotfiles to XDG dirs" "Preview everything" "Run everything" "Uninstall" \
			"Quit")" || break # Esc or Ctrl-C

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
			envsetup::dry_run && gum style --foreground 6 "Dry run: you are editing a copy of your config. Your changes last until you quit."
			envsetup::run_step envsetup::edit_config
			;;
		"Link shell config") envsetup::run_step envsetup::link_shell_config ;;
		"Set up zsh + oh-my-zsh") envsetup::run_step envsetup::set_up_zsh ;;
		"Configure git") envsetup::run_step envsetup::configure_git ;;
		"Install packages") envsetup::run_step envsetup::install_packages ;;
		"Run installers") envsetup::run_step envsetup::run_installers ;;
		"Move dotfiles to XDG dirs") envsetup::run_step envsetup::xdg_tidy ;;
		"Preview everything")
			gum style --bold "What Run everything would do for $label. Nothing changes:"
			ENVSETUP_DRY_RUN=1 envsetup::run_everything
			;;
		"Run everything")
			envsetup::dry_run && gum style --bold "Dry run: what Run everything would do for $label:"
			envsetup::run_everything
			;;
		"Uninstall")
			# After a real uninstall, the menu has nothing left to work on.
			if envsetup::uninstall && ! envsetup::dry_run; then break; fi
			;;
		*) break ;;
		esac
	done
}

gum style --border rounded --padding "1 2" --bold "envsetup $(envsetup::version)"
envsetup::dry_run && gum style --foreground 6 "Dry run: envsetup saves, installs and links nothing. Your choices and config edits last until you quit."
if ((UNINSTALL)); then
	# Uninstall needs the config to know which shell envsetup set up for your profile.
	envsetup::load_config "$(envsetup::read_state profile)" "$(envsetup::read_state mode full)"
	envsetup::uninstall || (($? == 2)) # a cancelled uninstall is not an error
	exit 0
fi
envsetup::main_menu
