# demo.tape records docs/tapes/demo.gif for the README.
# It runs in VHS's Docker image, and AGENTS.md shows the command.
# The recording is a dry run in an empty $HOME, so it changes nothing.

Output docs/tapes/demo.gif

Set Shell bash
Set FontSize 15
Set Width 1200
Set Height 760
Set Padding 20
Set TypingSpeed 60ms

# The image has no git or ssh-keygen, and envsetup uses both.
# safe.directory lets root read the mounted repo.
Hide
Type "export PS1='$ ' HOME=/home/me GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0='*'"
Enter
# The image's apt sources name "stable", so a new Debian release changes them.
Type "mkdir -p $HOME && apt-get update -qq --allow-releaseinfo-change && apt-get install -y -qq git openssh-client >/dev/null 2>&1 && echo RE''ADY"
Enter
# The quotes keep the typed command itself from matching.
# A failed install prints no READY, so the recording stops.
Wait+Screen@180s /READY/
Type "clear"
Enter
Sleep 500ms
Show

Type "./setup.sh --dry-run"
Sleep 500ms
Enter
Sleep 3s

# Select profile, then home.
Enter
Sleep 1500ms
Down
Sleep 500ms
Enter
Sleep 1500ms

# Preview everything is the 11th menu item.
Down 10
Sleep 1s
Enter
Sleep 7s

Escape
Sleep 1s
