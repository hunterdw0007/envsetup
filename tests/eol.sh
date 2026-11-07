#!/usr/bin/env bash
# This script tests .github/scripts/drop-eol-distros.sh.
# It runs a copy of the script in a temporary git repo with a small tests/distros/run.sh.
# The endoflife.date API is a folder of fixed JSON files, read through file:// URLs.
# So the test uses no network.
#
#   tests/eol.sh
#
# The test needs git, curl and jq.
set -uo pipefail # no -e, so one failed check does not stop the rest

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
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

# The fake API. Debian's eol is later than its support, so a check catches the wrong field.
api=$T/api
mkdir -p "$api/ubuntu" "$api/debian" "$api/opensuse"
echo '{"eol":"2029-05-31","support":"2026-01-01"}' >"$api/ubuntu/24.04.json"
echo '{"eol":"2028-06-30","support":"2026-07-11"}' >"$api/debian/12.json"
echo '{"eol":"2027-01-01"}' >"$api/opensuse/15.6.json"

list() {
	# shellcheck disable=SC2016 # run.sh's own code, which must not expand here
	printf '%s\n' '#!/usr/bin/env bash' 'images=("$@")' 'if ((${#images[@]} == 0)); then' $'\timages=(' \
		$'\t\t# Desktops' $'\t\tubuntu:24.04 debian:12' $'\t\t# Rolling' $'\t\tarchlinux:latest' \
		$'\t\topensuse/leap:15.6' "$@" $'\t)' 'fi'
}

# new_repo [extra run.sh line] makes a new repo in $T/repo.
new_repo() {
	rm -rf "$T/repo"
	mkdir -p "$T/repo/.github/scripts" "$T/repo/tests/distros"
	cp "$root/.github/scripts/drop-eol-distros.sh" "$T/repo/.github/scripts/"
	list "$@" >"$T/repo/tests/distros/run.sh"
	echo "Tested on Debian 12." >"$T/repo/README.md"
	git -C "$T/repo" init -q
	git -C "$T/repo" add -A
}

# run <today> runs the script and saves its output, its stderr and its exit code.
run() {
	EOL_TODAY=$1 EOL_API=file://$api "$T/repo/.github/scripts/drop-eol-distros.sh" >"$T/out" 2>"$T/err"
	rc=$?
}
unchanged() { git -C "$T/repo" diff --quiet -- tests/distros/run.sh; }
has() { grep -qF -- "$2" "$1"; }
lacks() { ! has "$@"; }

echo "== Nothing is past its date"
new_repo
# debian:12's support ends on this day, so it still counts.
run 2026-07-11
check "the script succeeds" test "$rc" -eq 0
check "run.sh is unchanged" unchanged
check "the output says so" has "$T/out" "still has security support on 2026-07-11"

echo "== debian:12 is past its date"
new_repo
run 2026-07-12
check "the script succeeds" test "$rc" -eq 0
list | sed 's/ debian:12$//' >"$T/want"
check "run.sh drops debian:12 and keeps the rest" cmp -s "$T/want" "$T/repo/tests/distros/run.sh"
check "the output names debian:12 and its date" has "$T/out" "\`debian:12\` (Debian 12): security support ended on 2026-07-11"
check "the output names the doc that still names Debian 12" has "$T/out" 'README.md:1:Tested on Debian 12.'
check "the output does not name ubuntu:24.04" lacks "$T/out" ubuntu

echo "== A line loses its only image"
new_repo ''
run 2027-01-02
list '' | sed -e 's/ debian:12$//' -e '/leap/d' >"$T/want"
check "run.sh drops the line with opensuse/leap:15.6 and keeps the blank line" cmp -s "$T/want" "$T/repo/tests/distros/run.sh"

echo "== An image line ends with a comment"
new_repo $'\t\tarchlinux:latest debian:12 # a note'
run 2026-07-12
list $'\t\tarchlinux:latest # a note' | sed 's/ debian:12$//' >"$T/want"
check "run.sh drops debian:12 and keeps the comment" cmp -s "$T/want" "$T/repo/tests/distros/run.sh"

echo "== An image has no row in the table"
new_repo $'\t\tgentoo/stage3:latest'
run 2030-01-01
check "the script fails" test "$rc" -ne 0
check "the error names the image" has "$T/err" "gentoo/stage3:latest has no row"
check "run.sh is unchanged" unchanged

echo "== An image with no row ends with a comment"
new_repo $'\t\tgentoo/stage3:latest # a note'
run 2026-01-01
check "the script fails" test "$rc" -ne 0
check "the error names the image" has "$T/err" "gentoo/stage3:latest has no row"

echo "== The PR step keeps fixes that people pushed to the branch"
# bump-pr.sh pushes to a local test remote, and a fake gh does nothing.
new_repo
cp "$root/.github/scripts/bump-pr.sh" "$T/repo/.github/scripts/"
mkdir -p "$T/bin"
printf '#!/bin/sh\nexit 0\n' >"$T/bin/gh"
chmod +x "$T/bin/gh"
git init -q --bare "$T/origin.git"
me=(-c user.name=me -c user.email=me@example.com)
git -C "$T/repo" add -A
git -C "$T/repo" "${me[@]}" commit -qm main
base=$(git -C "$T/repo" rev-parse HEAD)
git -C "$T/repo" remote add origin "$T/origin.git"
git -C "$T/repo" push -q origin HEAD:refs/heads/main
pr() {
	(cd "$T/repo" && PATH=$T/bin:$PATH GITHUB_REPOSITORY=me/envsetup BUMP_BRANCH=drop BUMP_COMPARE=list \
		BUMP_FILE=tests/distros/run.sh BUMP_TITLE="feat(distros): drop" .github/scripts/bump-pr.sh "$T/out") >"$T/pr.log" 2>&1
}
tip() { git -C "$T/origin.git" rev-parse -q --verify refs/heads/drop; }
run 2026-07-12
pr
check "the first run pushes the branch" test -n "$(tip)"
# A person pushes a fix to the branch.
git -C "$T/repo" checkout -q -- tests/distros/run.sh
git -C "$T/repo" checkout -q -B main "$base"
git -C "$T/repo" fetch -q origin drop
git -C "$T/repo" checkout -q FETCH_HEAD
echo "Tested on Debian 13." >"$T/repo/README.md"
git -C "$T/repo" "${me[@]}" commit -qam "docs: fix"
git -C "$T/repo" push -q origin HEAD:refs/heads/drop
fixed=$(git -C "$T/repo" rev-parse HEAD)
# Then run.sh changes on main.
git -C "$T/repo" checkout -q main
echo "# a change" >>"$T/repo/tests/distros/run.sh"
git -C "$T/repo" "${me[@]}" commit -qam "test: change run.sh"
git -C "$T/repo" push -q origin HEAD:refs/heads/main
run 2026-07-12
pr
check "a change on main keeps the fix" test "$(tip)" = "$fixed"
check "the PR step says the branch has the change" has "$T/pr.log" "drop already has this change"
git -C "$T/repo" checkout -q -- tests/distros/run.sh
run 2027-01-02
pr
check "another drop rewrites the branch" test "$(git -C "$T/origin.git" log -1 --format=%s drop)" = "feat(distros): drop"

echo "== A lookup fails"
new_repo
mv "$api/opensuse/15.6.json" "$T/saved.json"
# On this date, debian:12 and ubuntu:24.04 come before the failed lookup and are past their dates.
run 2030-01-01
mv "$T/saved.json" "$api/opensuse/15.6.json"
check "the script fails" test "$rc" -ne 0
check "run.sh is unchanged" unchanged

echo "== A field holds no date"
new_repo
echo '{"eol":false}' >"$api/ubuntu/24.04.json"
run 2026-01-01
check "the script fails" test "$rc" -ne 0
check "the error names the field" has "$T/err" "has no date in eol: false"
check "run.sh is unchanged" unchanged

if ((failures)); then
	echo "$failures check(s) failed."
	exit 1
fi
echo "Every check passed."
