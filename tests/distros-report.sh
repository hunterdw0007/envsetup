#!/usr/bin/env bash
# This script tests how tests/distros/run.sh reports results and sets its exit status.
# A fake docker on PATH plays the container, so the test uses no network and no real docker.
#
#   tests/distros-report.sh
#
# Run it as a user who is not root, because root can write a read-only file.
set -uo pipefail # no -e, so one failed check does not stop the rest

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T=$(mktemp -d)
trap 'chmod -R u+rwx "$T"; rm -rf "$T"' EXIT
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

if ((EUID == 0)); then
	echo "Run this test as a user who is not root." >&2
	exit 1
fi

# The fake docker. $FAKE_RUN picks what the container does.
#   pass        writes a PASS row for every phase and exits 0
#   fail        writes those rows and exits 1
#   stop        leaves summary.tsv empty and read-only, as root does with rootful Docker, and exits 1
#   stop-all    does the same to host.tsv too, so the host cannot write any row
#   partial     writes PASS rows, makes host.tsv read-only and exits 1
#   unreadable  writes PASS rows to a summary.tsv that the host cannot read, and exits 0
#   bootstrap   writes only the bootstrap row and exits 0
#   no-pull     fails every pull, as a registry that answers 429 does
#   half-pull   fails the pull of debian:13 only, and acts like pass for the other image
mkdir -p "$T/bin"
cat >"$T/bin/docker" <<'EOF'
#!/usr/bin/env bash
if [[ $1 == image || $1 == pull ]]; then
	[[ $FAKE_RUN == no-pull || ($FAKE_RUN == half-pull && $* == *debian*) ]] || exit 0
	[[ $1 == pull ]] && echo "toomanyrequests: You have reached your pull rate limit." >&2
	exit 1
fi
[[ $1 == run ]] || exit 0
while (($#)); do
	case $1 in
	-e) [[ $2 == DISTRO_SLUG=* ]] && slug=${2#*=} ;;
	-v) [[ $2 == *:/report ]] && out=${2%:/report} ;;
	esac
	shift
done
d=$out/$slug
mkdir -p "$d"
all() { for p in bootstrap gum home work-full work-lite; do printf '%s\t%s\tPASS\tok\n' "$slug" "$p"; done; }
case $FAKE_RUN in
pass | half-pull) all >"$d/summary.tsv" ;;
fail) all >"$d/summary.tsv" && exit 1 ;;
stop | stop-all)
	: >"$d/summary.tsv"
	chmod 444 "$d/summary.tsv"
	if [[ $FAKE_RUN == stop-all ]]; then
		: >"$d/host.tsv"
		chmod 444 "$d/host.tsv"
	fi
	exit 1
	;;
partial)
	all >"$d/summary.tsv"
	: >"$d/host.tsv"
	chmod 444 "$d/host.tsv"
	exit 1
	;;
unreadable)
	all >"$d/summary.tsv"
	chmod 000 "$d/summary.tsv"
	;;
bootstrap) printf '%s\tbootstrap\tPASS\tok\n' "$slug" >"$d/summary.tsv" ;;
esac
EOF
# run.sh waits 30 seconds between pulls, and the fake sleep skips that wait.
printf '#!/bin/sh\n' >"$T/bin/sleep"
chmod +x "$T/bin/docker" "$T/bin/sleep"

# scenario <fake> [<out>] runs run.sh for ubuntu:24.04 with that fake container.
# <out> names the report folder, so two scenarios can share one.
# $EXTRA names one more image to run.
# It sets $rc, $report and $log.
scenario() {
	local name=$1 dir=${2:-$1}
	echo "== $name${2:+ (in $2)}"
	rc=0
	FAKE_RUN=$name PATH="$T/bin:$PATH" DISTROS_OUT="$T/$dir" "$root/tests/distros/run.sh" ubuntu:24.04 ${EXTRA:+"$EXTRA"} >"$T/$dir.$name.log" 2>&1 || rc=$?
	report=$(cat "$T/$dir/report.md" 2>/dev/null)
	log=$(cat "$T/$dir.$name.log")
	check "run.sh wrote a report" test -n "$report"
}
# problem <text> checks that the report lists ubuntu:24.04 under Problems with that text.
problem() { grep -qF -- "- \`ubuntu:24.04\` $1" <<<"$report"; }
# no_none checks that the report is not empty and does not say "None.".
no_none() { [[ -n "$report" && "$report" != *$'\nNone.'* ]]; }

scenario pass
check "a passing run exits 0" test "$rc" -eq 0
check "a passing run reports no problems" grep -q '^None\.$' <<<"$report"

scenario fail
check "a container that exits 1 fails the run" test "$rc" -ne 0
check "the report lists the image under Problems" problem "**container** (FAIL): exited 1;"

scenario stop
check "a container that writes no rows fails the run" test "$rc" -ne 0
check "the report lists the image under Problems" problem "**container** (FAIL): exited 1 before any test ran"
check "the report does not say None" no_none

scenario stop-all
check "a row that the host cannot write fails the run" test "$rc" -ne 0
check "the shell says why" grep -q 'host.tsv: Permission denied' <<<"$log"
check "the report says a result is missing" grep -qF "run.sh hit an error" <<<"$report"

scenario partial
check "a lost FAIL row after PASS rows fails the run" test "$rc" -ne 0
check "the report says a result is missing" grep -qF "run.sh hit an error" <<<"$report"

scenario unreadable
check "an unreadable summary.tsv fails the run" test "$rc" -ne 0
check "the report names the unreadable file" problem "**container** (FAIL): couldn't read summary.tsv"

scenario bootstrap
check "a container that skips phases fails the run" test "$rc" -ne 0
check "the report names a missing phase" problem "**gum** (FAIL): no result"
check "the report names the last phase too" problem "**work-lite** (FAIL): no result"

scenario no-pull
check "a run where no image ran fails" test "$rc" -ne 0
check "the report keeps the pull WARN row" problem "**container** (WARN): couldn't pull the image"
check "the report says that no image ran" grep -qF "No image ran" <<<"$report"

EXTRA=debian:13 scenario half-pull
check "one failed pull next to an image that ran still exits 0" test "$rc" -eq 0
check "the report lists that pull as a WARN" grep -qF -- "- \`debian:13\` **container** (WARN)" <<<"$report"

scenario pass reused
scenario no-pull reused
check "a failed pull hides the old PASS rows" test "$(grep -c '✅' <<<"$report")" -eq 0

scenario pass locked
chmod 555 "$T/locked/ubuntu-24.04"
scenario no-pull locked
check "old rows that cannot be removed fail the run" test "$rc" -ne 0
check "the report says the results may be old" grep -qF "run.sh hit an error" <<<"$report"

echo
if ((failures)); then
	echo "$failures check(s) failed."
	exit 1
fi
echo "All checks passed."
