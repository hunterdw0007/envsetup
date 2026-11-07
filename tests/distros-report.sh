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
trap 'chmod -R u+w "$T"; rm -rf "$T"' EXIT
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
#   pass      writes PASS rows and exits 0
#   fail      writes PASS rows and exits 1
#   stop      leaves summary.tsv empty and read-only, as root does with rootful Docker, and exits 1
#   stop-all  does the same to host.tsv too, so the host cannot write any row
mkdir -p "$T/bin"
cat >"$T/bin/docker" <<'EOF'
#!/usr/bin/env bash
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
case $FAKE_RUN in
pass | fail)
	printf '%s\tbootstrap\tPASS\tok\n%s\thome\tPASS\tok\n' "$slug" "$slug" >"$d/summary.tsv"
	[[ $FAKE_RUN == pass ]]
	;;
stop | stop-all)
	: >"$d/summary.tsv"
	chmod 444 "$d/summary.tsv"
	if [[ $FAKE_RUN == stop-all ]]; then
		: >"$d/host.tsv"
		chmod 444 "$d/host.tsv"
	fi
	exit 1
	;;
esac
EOF
chmod +x "$T/bin/docker"

# scenario <name> runs run.sh for ubuntu:24.04 with that fake container.
# It sets $rc and $report.
scenario() {
	echo "== $1"
	rc=0
	FAKE_RUN=$1 PATH="$T/bin:$PATH" DISTROS_OUT="$T/$1" "$root/tests/distros/run.sh" ubuntu:24.04 >"$T/$1.log" 2>&1 || rc=$?
	report=$(cat "$T/$1/report.md" 2>/dev/null)
}

scenario pass
check "a passing run exits 0" test "$rc" -eq 0
check "a passing run reports no problems" grep -q '^None\.$' <<<"$report"

scenario fail
check "a container that exits 1 fails the run" test "$rc" -ne 0
check "the report lists the image under Problems" grep -q '^- .ubuntu:24.04. \*\*container\*\* (FAIL)' <<<"$report"

scenario stop
check "a container that writes no rows fails the run" test "$rc" -ne 0
check "the report lists the image under Problems" grep -q '^- .ubuntu:24.04. \*\*container\*\* (FAIL)' <<<"$report"
check "the report does not say None" test "$(grep -c '^None\.$' <<<"$report")" -eq 0

scenario stop-all
check "a row that the host cannot write fails the run" test "$rc" -ne 0

echo
if ((failures)); then
	echo "$failures check(s) failed."
	exit 1
fi
echo "All checks passed."
