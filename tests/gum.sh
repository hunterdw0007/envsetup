#!/usr/bin/env bash
# gum stand-in for the tests (smoke.sh, macos.sh and distros/ copy it onto PATH as `gum`):
# answers `choose` from $SMOKE_CHOICES (one per line; "ESC", or running out, cancels),
# `confirm` from $SMOKE_CONFIRMS (only "yes" accepts; running out declines), fills
# `input`, and logs every call to $SMOKE_LOG. Bash 3.2 and BSD tools: macOS runs it too.

echo "gum $*" >>"$SMOKE_LOG"
# pop <file>: prints its first line and removes it.
pop() {
	head -n 1 "$1" 2>/dev/null
	tail -n +2 "$1" >"$1.tmp" 2>/dev/null
	mv "$1.tmp" "$1"
}
case $1 in
choose)
	answer=$(pop "$SMOKE_CHOICES")
	if [[ -z $answer || $answer == ESC ]]; then exit 1; fi
	echo "$answer"
	;;
confirm) [[ $(pop "$SMOKE_CONFIRMS") == yes ]] ;;
# SMOKE_INPUT: ESC cancels (gum exits 1), any other value is the answer.
input)
	if [[ ${SMOKE_INPUT-unset} == ESC ]]; then exit 1; fi
	if [[ ${SMOKE_INPUT-unset} != unset ]]; then
		echo "$SMOKE_INPUT"
	elif [[ $* == *@* ]]; then
		echo smoke@example.com
	else
		echo "Smoke Test"
	fi
	;;
style) echo "${*: -1}" ;;
esac
