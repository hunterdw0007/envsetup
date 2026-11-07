#!/usr/bin/env bash
# This file loads the settings that setup.sh acts on.
# It loads the repo's defaults first, then the user's config.sh.
# config.example.sh documents the settings.
# shellcheck disable=SC2034 # setup.sh, lib/*.sh and the user's config read the ENVSETUP_* variables

ENVSETUP_USER_CONFIG="$ENVSETUP_STATE/config.sh"
# The clone of the user's own config repo (see envsetup::sync_config_repo).
ENVSETUP_CONFIG_CLONE="$ENVSETUP_STATE/repo"
# ENVSETUP_RENAMED lists the settings that got a new name.
# Each item is "<old name>=<new name>", for example "ENVSETUP_OLD=ENVSETUP_NEW".
# load_config still reads each old name.
# envsetup::migrate_config asks to write the new name into config.sh.
# With an item here, a rename is not a breaking change (see docs/interface.md).
ENVSETUP_RENAMED=()

envsetup::load_config() {
	ENVSETUP_PROFILE=$1
	ENVSETUP_MODE=$2

	readarray -t ENVSETUP_PACKAGES < <(grep -hvE '^\s*(#|$)' \
		"$ENVSETUP_ROOT/packages/common.txt" "$ENVSETUP_ROOT/packages/$ENVSETUP_PROFILE.txt" 2>/dev/null)
	readarray -t ENVSETUP_GIT_CONFIG < <(git config --file "$ENVSETUP_ROOT/git/gitconfig" --list)
	ENVSETUP_INSTALLER_DIRS=("$ENVSETUP_ROOT/installers/common" "$ENVSETUP_ROOT/installers/$ENVSETUP_PROFILE")
	ENVSETUP_EXTRAS=()
	ENVSETUP_SKIP=()
	ENVSETUP_SHELL=bash
	ENVSETUP_XDG_NINJA=0

	[[ -f "$ENVSETUP_USER_CONFIG" ]] || return 0
	# Each interactive shell also sources config.sh.
	# So config.sh may not work under set -e or set -u.
	# This function loads config.sh with -e and -u off.
	# Afterwards, it turns the caller's options back on.
	# A syntax error or a failed command then gives one warning.
	# config.sh can see and change this function's local variables.
	# So the local names have a prefix.
	local _envsetup_opts=$- _envsetup_err='' _envsetup_line='' _envsetup_trap
	if ! _envsetup_err=$("$BASH" -n "$ENVSETUP_USER_CONFIG" 2>&1); then
		_envsetup_err=${_envsetup_err%%$'\n'*}
		_envsetup_err="${_envsetup_err#"$ENVSETUP_USER_CONFIG: "}"
	else
		_envsetup_err=
	fi
	_envsetup_trap=$(trap -p ERR)
	# Only a failed command in config.sh itself counts.
	# config.sh may end with a false `[[ ... ]] && ...`.
	# Then `source` below returns 1, but that is not an error.
	trap 'if [[ ${BASH_SOURCE[0]} == "$ENVSETUP_USER_CONFIG" ]]; then _envsetup_line=${_envsetup_line:-$LINENO}; fi' ERR
	set +eu
	# shellcheck source=/dev/null # the user's own file
	source "$ENVSETUP_USER_CONFIG"
	trap - ERR
	eval "$_envsetup_trap"
	if [[ $_envsetup_opts == *e* ]]; then set -e; fi
	if [[ $_envsetup_opts == *u* ]]; then set -u; fi
	# An old name from ENVSETUP_RENAMED sets the new name.
	# So a config.sh that the user did not migrate still works.
	local _envsetup_item
	for _envsetup_item in "${ENVSETUP_RENAMED[@]}"; do
		if declare -p "${_envsetup_item%%=*}" >/dev/null 2>&1; then
			local -n _envsetup_old=${_envsetup_item%%=*} _envsetup_new=${_envsetup_item#*=}
			_envsetup_new=("${_envsetup_old[@]}")
		fi
	done
	if [[ -n "$_envsetup_err" ]]; then
		envsetup::config_warning "$ENVSETUP_USER_CONFIG did not load completely ($_envsetup_err). envsetup uses the settings before the error."
	elif [[ -n "$_envsetup_line" ]]; then
		envsetup::config_warning "In $ENVSETUP_USER_CONFIG, the command on line $_envsetup_line failed. envsetup continues with the other settings."
	fi
}

# config_warning <text> shows the text only once, until the text changes.
# The menu loads config.sh again each time it shows, so the same warning would repeat.
envsetup::config_warning() {
	if [[ "$1" != "${ENVSETUP_CONFIG_WARNED:-}" ]]; then
		ENVSETUP_CONFIG_WARNED=$1
		# setup.sh --status runs without gum.
		if envsetup::has_cmd gum; then gum style --foreground 3 "$1" >&2; else printf '%s\n' "$1" >&2; fi
	fi
}

# work lite does not assume sudo, so it runs no packages and no installers.
envsetup::lite() { [[ "$ENVSETUP_PROFILE" == work && "$ENVSETUP_MODE" == lite ]]; }

envsetup::skipped() {
	[[ " ${ENVSETUP_SKIP[*]:-} " == *" $1 "* ]]
}

# resolved_packages prints what "Install packages" installs.
# That is ENVSETUP_PACKAGES without duplicates and without ENVSETUP_SKIP.
# Descriptions and previews of packages use this function too.
# So they always match what runs.
envsetup::resolved_packages() {
	local pkg
	local -A seen=()
	for pkg in "${ENVSETUP_PACKAGES[@]}"; do
		[[ -z "$pkg" || -n "${seen[$pkg]:-}" ]] && continue
		seen[$pkg]=1
		envsetup::skipped "$pkg" || echo "$pkg"
	done
}

# resolved_installers prints what "Run installers" runs, in order.
# First come all *.sh files in ENVSETUP_INSTALLER_DIRS.
# Then come the installers/extras/ scripts that ENVSETUP_EXTRAS names.
# It leaves out ENVSETUP_SKIP.
# An installer's name is its script name without .sh.
envsetup::resolved_installers() {
	local dir script name scripts=()
	for dir in "${ENVSETUP_INSTALLER_DIRS[@]}"; do
		scripts+=("$dir"/*.sh)
	done
	for name in "${ENVSETUP_EXTRAS[@]}"; do
		script=$ENVSETUP_ROOT/installers/extras/$name.sh
		if [[ -f "$script" ]]; then
			scripts+=("$script")
		else
			echo "ENVSETUP_EXTRAS: no installer for \"$name\" (see installers/extras/)" >&2
		fi
	done
	for script in "${scripts[@]}"; do
		[[ -f "$script" ]] || continue
		name=${script##*/}
		envsetup::skipped "${name%.sh}" || echo "$script"
	done
}

# sync_config_repo gets config.sh from the user's own git repo.
# The first run clones ENVSETUP_CONFIG_REPO into ENVSETUP_CONFIG_CLONE.
# Setting ENVSETUP_CONFIG_REPO is the user's choice to clone.
# Later runs ask before they pull the clone.
# They do not need ENVSETUP_CONFIG_REPO.
# Then config.sh becomes a symlink to the config.sh in the clone.
# The function asks before it replaces a config.sh of the user's own.
# It moves that file to config.sh.bak first.
# If the user keeps their own config.sh, later runs neither ask nor pull.
# A failed clone or pull shows a warning.
# The menu still opens.
envsetup::sync_config_repo() {
	local url=${ENVSETUP_CONFIG_REPO:-} repo=$ENVSETUP_CONFIG_CLONE link=$ENVSETUP_STATE/config.sh origin rc=0
	if [[ -n "$url" ]]; then
		# The short form "me" means github.com/me/envsetup-config.
		if [[ "$url" != */* && "$url" != *:* ]]; then url=github.com/$url/envsetup-config; fi
		# The short form "me/dotfiles" means github.com/me/dotfiles.
		if [[ "$url" =~ ^[^/:.]+/[^/:]+$ ]]; then url=github.com/$url; fi
		# A URL without a scheme, such as github.com/me/dotfiles, uses https.
		if [[ "$url" != *:* && "$url" != /* ]]; then url=https://$url; fi
	fi
	if [[ -d "$repo/.git" ]]; then
		origin=$(git -C "$repo" remote get-url origin 2>/dev/null) || origin=
		if [[ -n "$url" && "$url" != "$origin" ]]; then
			gum style --foreground 3 "ENVSETUP_CONFIG_REPO is $url, but $repo comes from ${origin:-an unknown URL}. envsetup keeps using $repo."
		fi
		# The user kept their own config.sh, so the clone does not matter to this run.
		if [[ (-e "$link" || -L "$link") && "$(readlink "$link")" != "$repo/config.sh" ]]; then return 0; fi
		if envsetup::dry_run; then
			envsetup::would "ask to pull $repo"
		elif gum confirm "Pull your config repo ($repo) before the menu opens?"; then
			if ! git -C "$repo" pull -q --ff-only; then
				gum style --foreground 3 "Couldn't pull $repo. Commit and push your edits there, or undo them. envsetup uses the config.sh that it has."
			fi
		fi
	elif [[ -n "$url" ]]; then
		if envsetup::dry_run; then
			envsetup::would "clone $url into $repo"
			envsetup::would "link $link to $repo/config.sh"
			return 0
		fi
		if ! git clone -q -- "$url" "$repo"; then
			gum style --foreground 3 "Couldn't clone $url. Check ENVSETUP_CONFIG_REPO, then run setup again. The menu opens without your repo."
			return 0
		fi
		gum style --foreground 2 "Cloned $url into $repo"
	else
		return 0
	fi

	if [[ ! -f "$repo/config.sh" ]]; then
		gum style --foreground 3 "$repo has no config.sh, so envsetup links none."
		return 0
	fi
	if [[ -L "$link" && "$(readlink "$link")" == "$repo/config.sh" ]]; then return 0; fi
	# Only a run that just cloned gets here with a config.sh of the user's own, so this is never a dry run.
	if [[ -e "$link" || -L "$link" ]]; then
		# Only a clear no (exit 1) replaces the file. Ctrl-C keeps it.
		gum confirm "Keep your own $link? No moves it to $link.bak and links $repo/config.sh instead." || rc=$?
		if ((rc != 1)); then return 0; fi
		if [[ -e "$link.bak" || -L "$link.bak" ]]; then
			gum style --foreground 3 "$link.bak already exists, so envsetup keeps $link as it is."
			return 0
		fi
		mv "$link" "$link.bak"
		gum style --foreground 2 "Moved your old config.sh to $link.bak"
	fi
	if envsetup::dry_run; then
		envsetup::would "link $link to $repo/config.sh"
		return 0
	fi
	ln -sfn "$repo/config.sh" "$link"
	gum style --foreground 2 "Linked $link to $repo/config.sh"
}

# migrate_config asks to rename the old names from ENVSETUP_RENAMED in config.sh.
# It changes only whole words that match an old name.
# A dry run only describes the change.
# After a "no", load_config still reads the old names, and the next run asks again.
envsetup::migrate_config() {
	local file=$ENVSETUP_USER_CONFIG item text tok out='' found=() list=''
	[[ -f "$file" ]] || return 0
	for item in "${ENVSETUP_RENAMED[@]}"; do
		if grep -qw -- "${item%%=*}" "$file"; then
			found+=("$item")
			list+=" ${item%%=*} → ${item#*=}"
		fi
	done
	((${#found[@]})) || return 0
	if envsetup::dry_run; then
		# A dry run's file is a temporary copy, so name the real file.
		envsetup::would "ask to rename these settings in $ENVSETUP_STATE/config.sh:$list"
		return 0
	fi
	if ! gum confirm "Some settings in $file have a new name:$list. Rename them in $file?"; then
		gum style --foreground 3 "envsetup keeps $file as it is and reads the old names. The next run asks again."
		return 0
	fi
	IFS= read -rd '' text <"$file" || true
	# Split the text into words and the text between words, so only whole words change.
	while [[ "$text" =~ ^([A-Za-z0-9_]+|[^A-Za-z0-9_]+) ]]; do
		tok=${BASH_REMATCH[0]}
		text=${text:${#tok}}
		for item in "${found[@]}"; do
			if [[ "$tok" == "${item%%=*}" ]]; then tok=${item#*=}; fi
		done
		out+=$tok
	done
	# The loop stops early at bytes that are not valid text, so add the rest as it is.
	out+=$text
	printf '%s' "$out" >"$file"
	gum style --foreground 2 "Renamed the settings in $file:$list"
	envsetup::warn_config_repo
}

# warn_config_repo warns when config.sh links into the clone of the user's config repo.
# A dry run edits a plain copy, so it gets no warning.
envsetup::warn_config_repo() {
	if [[ -L "$ENVSETUP_USER_CONFIG" ]]; then
		gum style --foreground 3 "This config.sh is in your config repo. Commit and push your edits there, or a later pull fails."
	fi
}

# edit_config opens config.sh in $EDITOR.
# Without $EDITOR, it uses nano if the machine has it, and vi otherwise.
envsetup::edit_config() {
	# A link to a file that is gone would make cp below write into the clone.
	if [[ -L "$ENVSETUP_USER_CONFIG" && ! -e "$ENVSETUP_USER_CONFIG" ]]; then
		gum style --foreground 3 "$ENVSETUP_USER_CONFIG linked to a file that is gone. Edit config replaces the link with a new config.sh."
		rm -f "$ENVSETUP_USER_CONFIG"
	fi
	if [[ ! -f "$ENVSETUP_USER_CONFIG" ]]; then
		mkdir -p "${ENVSETUP_USER_CONFIG%/*}"
		cp "$ENVSETUP_ROOT/config.example.sh" "$ENVSETUP_USER_CONFIG"
	fi
	envsetup::warn_config_repo
	local before editor=(vi)
	before=$(envsetup::settings_of "$ENVSETUP_USER_CONFIG")
	if [[ -n "${EDITOR:-}" ]]; then
		read -ra editor <<<"$EDITOR"
	elif envsetup::has_cmd nano; then
		editor=(nano)
	fi
	"${editor[@]}" "$ENVSETUP_USER_CONFIG"
	envsetup::check_config "$ENVSETUP_USER_CONFIG" "$ENVSETUP_USER_CONFIG has an error. Select Edit config to fix it:"
	envsetup::show_changes "$before" "$(envsetup::settings_of "$ENVSETUP_USER_CONFIG")"
}

# paste_config saves the text that you paste.
# It asks where the text goes: the end of config.sh, or a new file in shell.d.
envsetup::paste_config() {
	local text choice
	# gum shows its own keys to save and to cancel under the box.
	# The keys differ between gum releases.
	text=$(gum write --char-limit 0 --height 15 --show-line-numbers \
		--header "Paste your settings or shell code.") || return 0
	printf '%s\n' "$text" >"$ENVSETUP_TMP/paste.sh"
	choice=$(gum choose --header "Where does the text go?" \
		"settings  the end of config.sh" \
		"shell  a new file in shell.d, next to config.sh") || return 0
	if [[ "${choice%% *}" == shell ]]; then
		envsetup::add_shell_file "$ENVSETUP_TMP/paste.sh"
	else
		envsetup::add_config "$ENVSETUP_TMP/paste.sh"
	fi
}

# add_shell_file <file> saves the file's text as a new file in shell.d.
# It asks for the name.
# It saves nothing if a shell that loads the file finds a syntax error, or if the file stops before its end.
# It asks before it replaces a file, and the default answer keeps the old file.
envsetup::add_shell_file() {
	local text name file sh opt shells=()
	text=$(<"$1")
	text=${text//$'\r'/}
	if [[ -z "${text//[[:space:]]/}" ]]; then
		gum style --foreground 3 "The text is empty, so envsetup saved nothing."
		return 0
	fi
	printf '%s\n' "$text" >"$ENVSETUP_TMP/add.sh"
	name=$(gum input --placeholder aliases.sh \
		--header "File name. New bash and zsh shells load .sh files. Only bash loads .bash, and only zsh loads .zsh.") || return 0
	if [[ -z "$name" ]]; then return 0; fi # an empty name is a cancel
	# The function shows its own message, so a bad name is not a failed step.
	if [[ ! "$name" =~ ^[[:alnum:]_][[:alnum:]._-]*$ ]]; then
		gum style --foreground 3 "\"$name\" is not a file name, so envsetup saved nothing. Use letters, digits, dots, dashes and underscores."
		return 0
	fi
	# shell/init.sh skips a file without one of these endings.
	if [[ ! "$name" =~ \.(sh|bash|zsh)$ ]]; then name+=.sh; fi
	# Each shell that loads the file checks it.
	if [[ "$name" != *.zsh ]]; then shells+=("$BASH"); fi
	if [[ "$name" != *.bash ]] && envsetup::has_cmd zsh; then shells+=(zsh); fi
	if ((${#shells[@]} == 0)); then
		gum style --foreground 3 "zsh is not installed, so envsetup cannot check $name."
	fi
	for sh in "${shells[@]}"; do
		envsetup::check_config "$ENVSETUP_TMP/add.sh" "The text has an error in ${sh##*/}, so envsetup saved nothing:" "$sh"
		# A file that runs exit would close every new shell.
		# zsh -f skips the user's own zsh startup files.
		# bash -f means something else (no globs), so bash gets only -c.
		opt=-c
		if [[ "$sh" == zsh ]]; then opt=-fc; fi
		# shellcheck disable=SC2016 # $1 expands in the inner shell
		if [[ "$("$sh" "$opt" '. "$1" >/dev/null 2>&1; echo envsetup-ok' sh "$ENVSETUP_TMP/add.sh" 2>/dev/null </dev/null)" != envsetup-ok ]]; then
			gum style --foreground 1 "The text stops before its end in ${sh##*/}, for example at an exit." \
				"Every new shell would then close. So envsetup saved nothing."
			return 1
		fi
	done
	# shellcheck disable=SC2153 # lib/common.sh sets ENVSETUP_SHELL_D, and it is not a misspelling of ENVSETUP_SHELL
	file=$ENVSETUP_SHELL_D/$name
	if [[ -e "$file" || -L "$file" ]]; then
		if envsetup::dry_run; then
			envsetup::would "ask to replace $file"
			return 0
		fi
		if ! gum confirm --default=false "Replace $name?"; then
			gum style "envsetup kept the old $name and saved nothing."
			return 0
		fi
	fi
	if envsetup::dry_run; then
		envsetup::would "save the text as $file"
		return 0
	fi
	mkdir -p "$ENVSETUP_SHELL_D"
	# Replace a link itself, not the file that it points to.
	rm -f "$file"
	cat "$ENVSETUP_TMP/add.sh" >"$file"
	gum style --foreground 2 "Saved $file. New interactive shells load it."
}

# add_config <file> adds the file's text to the end of config.sh.
# It saves nothing if the text is empty, or if bash -n finds an error in the text or in config.sh.
# It also saves nothing if config.sh would stop before its end, for example at an exit.
# Paste config and setup.sh --config use it.
envsetup::add_config() {
	local text before after new=$ENVSETUP_TMP/config.new
	text=$(<"$1")
	# A paste from Windows (WSL) has \r at the end of each line, and bash reads it as part of the command.
	text=${text//$'\r'/}
	if [[ -z "${text//[[:space:]]/}" ]]; then
		gum style --foreground 3 "The text is empty, so envsetup saved nothing."
		return 0
	fi
	printf '%s\n' "$text" >"$ENVSETUP_TMP/add.sh"
	envsetup::check_config "$ENVSETUP_TMP/add.sh" "The text has an error, so envsetup saved nothing:"
	if [[ -f "$ENVSETUP_USER_CONFIG" ]]; then
		envsetup::check_config "$ENVSETUP_USER_CONFIG" "config.sh already has an error, so envsetup saved nothing. Select Edit config to fix it:"
	fi
	: >"$new"
	if [[ -f "$ENVSETUP_USER_CONFIG" ]]; then cat "$ENVSETUP_USER_CONFIG" >"$new"; fi
	# A last line without a newline would join the first new line.
	if [[ -s "$new" && -n "$(tail -c 1 "$new")" ]]; then echo >>"$new"; fi
	printf '%s\n' "$text" >>"$new"
	envsetup::check_config "$new" "config.sh with the text at its end has an error, so envsetup saved nothing:"
	before=$(envsetup::settings_of "$ENVSETUP_USER_CONFIG")
	after=$(envsetup::settings_of "$new")
	if [[ -z "$after" ]]; then
		gum style --foreground 1 "config.sh with the text would stop before its end, for example at an exit." \
			"A new shell would then close. So envsetup saved nothing."
		return 1
	fi
	mkdir -p "${ENVSETUP_USER_CONFIG%/*}"
	cat "$new" >"$ENVSETUP_USER_CONFIG"
	if envsetup::dry_run; then
		gum style --foreground 2 "Added the text to this session's copy of config.sh. The copy lasts until you quit."
	else
		gum style --foreground 2 "Added the text to the end of $ENVSETUP_USER_CONFIG"
	fi
	envsetup::show_changes "$before" "$after"
	envsetup::warn_config_repo
}

# check_config <file> <message> [shell] checks the file with bash -n, or with `<shell> -n`.
# On a syntax error, it shows the message and the error with its line number.
# Then it returns 1.
envsetup::check_config() {
	local err
	if err=$("${3:-$BASH}" -n "$1" 2>&1); then return 0; fi
	# bash writes "<file>: line 2: …", and zsh writes "<file>:2: …".
	err=${err//"$1: "/}
	gum style --foreground 1 "$2" "${err//"$1:"/line }"
	return 1
}

# show_changes reports these settings.
# Each item is "<label>:<variable name without ENVSETUP_>".
ENVSETUP_SETTINGS=(Packages:PACKAGES Extras:EXTRAS Skip:SKIP Shell:SHELL "XDG ninja:XDG_NINJA"
	"Git config:GIT_CONFIG" "Installer dirs:INSTALLER_DIRS")

# settings_of <file> loads the settings with that file as config.sh.
# It prints one "<label>|<value>" line for each value.
# It runs in a subshell, so the menu's own settings stay the same.
# A config.sh that runs exit ends the subshell early, so settings_of then prints nothing.
envsetup::settings_of() {
	(
		ENVSETUP_USER_CONFIG=$1
		envsetup::load_config "${ENVSETUP_PROFILE:-}" "${ENVSETUP_MODE:-full}" >/dev/null 2>&1
		for setting in "${ENVSETUP_SETTINGS[@]}"; do
			var="ENVSETUP_${setting#*:}[@]"
			for value in "${!var}"; do printf '%s|%s\n' "${setting%%:*}" "$value"; done
		done
	) || true # an exit 1 in config.sh must not end the caller under set -e
}

# show_changes <before> <after> compares two outputs of settings_of.
# It shows each setting that changed, for example "Packages: +neovim +zoxide".
envsetup::show_changes() {
	local setting label line out any=0
	local -A old=() new=()
	if [[ -z "$2" ]]; then
		gum style --foreground 3 "config.sh stops before its end, for example at an exit. So envsetup cannot show the changed settings."
		return 0
	fi
	while IFS= read -r line; do if [[ -n "$line" ]]; then old[$line]=1; fi; done <<<"$1"
	while IFS= read -r line; do if [[ -n "$line" ]]; then new[$line]=1; fi; done <<<"$2"
	for setting in "${ENVSETUP_SETTINGS[@]}"; do
		label=${setting%%:*} out=
		while IFS= read -r line; do
			if [[ "$line" == "$label|"* && -z "${old[$line]:-}" ]]; then out+=" +${line#*|}"; fi
		done <<<"$2"
		while IFS= read -r line; do
			if [[ "$line" == "$label|"* && -z "${new[$line]:-}" ]]; then out+=" -${line#*|}"; fi
		done <<<"$1"
		if [[ -n "$out" ]]; then
			gum style "$label:$out"
			any=1
		fi
	done
	if ((any == 0)); then gum style "No ENVSETUP_* setting changed."; fi
}
