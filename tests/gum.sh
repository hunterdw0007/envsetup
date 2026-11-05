#!/usr/bin/env bash
# This is a fake gum for the tests.
# smoke.sh and distros/ copy it onto PATH as `gum`.
# It answers `choose` from $SMOKE_CHOICES, one answer per line.
# "ESC", or no answer left, cancels.
# It answers `confirm` from $SMOKE_CONFIRMS.
# Only "yes" accepts, and no answer left declines.
# It fills in `input` and `write`, and it logs every call to $SMOKE_LOG.

echo "gum $*" >>"$SMOKE_LOG"
# pop <file> prints the file's first line and removes it.
pop() {
	head -n 1 "$1" 2>/dev/null
	tail -n +2 "$1" >"$1.tmp" 2>/dev/null
	mv "$1.tmp" "$1"
}
case $1 in
choose)
	answer=$(pop "$SMOKE_CHOICES")
	if [[ -z $answer || $answer == ESC ]]; then exit 1; fi
	# SIGINT and SIGTERM act like Ctrl-C or a kill on the terminal's foreground job.
	if [[ $answer == SIG* ]]; then kill -s "${answer#SIG}" 0; fi
	echo "$answer"
	;;
confirm) [[ $(pop "$SMOKE_CONFIRMS") == yes ]] ;;
# SMOKE_INPUT=ESC cancels, and gum exits 1.
# Any other value is the answer.
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
# `write` prints $SMOKE_WRITE.
# SMOKE_WRITE=ESC, or no SMOKE_WRITE, cancels, and gum exits 1.
write)
	if [[ ${SMOKE_WRITE-ESC} == ESC ]]; then exit 1; fi
	printf '%s\n' "$SMOKE_WRITE"
	;;
style) echo "${*: -1}" ;;
esac
