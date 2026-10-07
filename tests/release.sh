#!/usr/bin/env bash
# Tests .github/scripts/release.sh, the only code that pushes to main. Each run is what
# CI's release job does: a fresh checkout of the pushed commit, `release.sh bump`, then
# `release.sh publish`, here against a scratch origin, with real git and commitizen and a
# stand-in gh. The origin starts from this checkout's files (uncommitted edits included),
# with no releases yet.
#
#   tests/release.sh
#
# Needs git and cz on PATH (pipx install commitizen, or CI's
# .github/actions/commitizen). Runs in a temp dir and changes nothing else.
# shellcheck disable=SC2016 # single-quoted code is meant to expand in the stub
set -uo pipefail # no -e: one failed check doesn't stop the rest

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
O=$T/origin.git
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
fails() { ! "$@"; }
show() { sed 's/^/        | /' "$1"; }

command -v cz >/dev/null || {
	echo "tests/release.sh needs commitizen's cz on PATH (pipx install commitizen)." >&2
	exit 2
}

# gh: a release exists once it's created (its notes are kept in $GH_STATE/<tag>).
export GH_LOG=$T/gh.log GH_STATE=$T/releases
mkdir -p "$T/bin" "$T/nocz" "$GH_STATE"
cat >"$T/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >>"$GH_LOG"
case "$1 $2" in
"release view") [[ -f "$GH_STATE/$3" ]] ;;
"release create")
	tag=$3
	while (($#)); do
		if [[ $1 == --notes-file ]]; then cp "$2" "$GH_STATE/$tag"; fi
		shift
	done ;;
*) exit 1 ;;
esac
EOF
# publish runs with a cz that fails, so it can't depend on commitizen (see release.sh).
printf '#!/bin/sh\necho "publish ran cz" >&2\nexit 99\n' >"$T/nocz/cz"
chmod +x "$T/bin/gh" "$T/nocz/cz"
export PATH=$T/bin:$PATH GITHUB_REPOSITORY=owner/envsetup GITHUB_SERVER_URL=https://github.example
unset PUSH_TOKEN GH_TOKEN

dev=(-c user.name=dev -c user.email=dev@example.com)
git init -q --bare "$O"
git -C "$O" symbolic-ref HEAD refs/heads/main
git init -q "$T/seed"
(cd "$root" && git ls-files -z --cached --others --exclude-standard | tar --null -T - -cf -) | tar -xf - -C "$T/seed"
# No releases yet, so CHANGELOG.md is just its header: the real one has every entry,
# for tags this origin doesn't have.
sed -i '/^## /,$d' "$T/seed/CHANGELOG.md"
git -C "$T/seed" add -A
git -C "$T/seed" "${dev[@]}" commit -qm "chore: the code under test"
git -C "$T/seed" push -q "$O" HEAD:main

# commit <git commit args...>: a commit on the origin's main, as a merged PR; prints it.
commit() {
	rm -rf "${T:?}/dev"
	git clone -q "$O" "$T/dev"
	git -C "$T/dev" "${dev[@]}" commit -q --allow-empty "$@"
	git -C "$T/dev" push -q origin HEAD:main
	git -C "$T/dev" rev-parse HEAD
}
# release <sha>: CI's release job for that pushed commit; output in $T/out.
release() {
	rm -rf "${T:?}/ci"
	git clone -q "$O" "$T/ci"
	git -C "$T/ci" checkout -q --detach "$1"
	: >"$GH_LOG"
	(
		cd "$T/ci" || exit 1
		export GITHUB_SHA=$1
		.github/scripts/release.sh bump && PATH=$T/nocz:$PATH .github/scripts/release.sh publish
	) >"$T/out" 2>&1
}
tags() { [ "$(git -C "$O" tag --sort=v:refname | tr '\n' ' ')" = "$1" ]; }
main_is() { [ "$(git -C "$O" rev-parse main)" = "$1" ]; }
main_subject() { [ "$(git -C "$O" log -1 --format=%s main)" = "$1" ]; }
created() { [ "$(grep -c "^gh release create $1 " "$GH_LOG")" = 1 ]; }
none_created() { ! grep -q '^gh release create' "$GH_LOG"; }
notes_have() { grep -qxF -- "$2" "$GH_STATE/$1"; }
# notes_are_entry <tag>: the notes, up to the install instructions, are in CHANGELOG.md word for word.
notes_are_entry() {
	local notes
	notes=$(sed '/^### Install this version$/,$d' "$GH_STATE/$1")
	[[ -n "$notes" && "$(git -C "$O" show main:CHANGELOG.md)" == *"$notes"* ]]
}
# section <tag> <heading>: the bullets under "### <heading>" in that release's notes.
section() { sed -n "/^### $2\$/,/^###/{/^- /p}" "$GH_STATE/$1"; }

echo "== first release: everything so far, on 0.x"
commit -m "feat: a feature" >/dev/null
commit -m "fix(home): a fix" >/dev/null
commit -m "chore!: drop something" >/dev/null
commit -m "feat(work)!: change something" >/dev/null
first=$(commit -m "refactor: tidy" -m "BREAKING CHANGE: the footer explains")
check "exits 0" release "$first"
check "tags v0.1.0 (breaking changes bump the minor version on 0.x)" tags "v0.1.0 "
check "pushes a bump commit to main" main_subject "bump: version 0.0.0 → 0.1.0"
check "  ...as github-actions[bot]" [ "$(git -C "$O" log -1 --format=%an main)" = "github-actions[bot]" ]
check "  ...right after the released commit" [ "$(git -C "$O" rev-parse main~1)" = "$first" ]
check "the tag is annotated" [ "$(git -C "$O" cat-file -t v0.1.0)" = tag ]
check "  ...and on the bump commit" [ "$(git -C "$O" rev-parse 'v0.1.0^{commit}')" = "$(git -C "$O" rev-parse main)" ]
check "CHANGELOG.md keeps its header" [ "$(git -C "$O" show main:CHANGELOG.md | head -n 1)" = "# Changelog" ]
check "  ...and gains the entry" grep -qx '## v0.1.0 (.*)' <(git -C "$O" show main:CHANGELOG.md)
check "publishes one release" created v0.1.0
check "its notes start with the breaking changes" [ "$(head -n 1 "$GH_STATE/v0.1.0")" = "### Breaking changes" ]
check "  ...all three kinds of them" [ "$(section v0.1.0 'Breaking changes' | sort | tr '\n' '|')" = "- **work**: change something|- drop something|- the footer explains|" ]
check "  ...and the rest by type" [ "$(section v0.1.0 Fixes)" = "- **home**: a fix" ]
check "  ...with a blank line before the install instructions" [ -z "$(grep -B1 '^### Install this version$' "$GH_STATE/v0.1.0" | head -n 1)" ]
check "  ...which pin this version" notes_have v0.1.0 "curl -fsSL https://raw.githubusercontent.com/owner/envsetup/main/install.sh | ENVSETUP_VERSION=v0.1.0 bash"
check "the notes are the CHANGELOG.md entry" notes_are_entry v0.1.0
((failures)) && show "$T/out"
bumped=$(git -C "$O" rev-parse main)

echo "== re-running the same commit"
rm "$GH_STATE/v0.1.0"
check "with its release missing: exits 0" release "$first"
check "  ...creates just the release" created v0.1.0
check "  ...without another tag or commit" tags "v0.1.0 "
check "  ...or moving main" main_is "$bumped"
check "with its release there: exits 0" release "$first"
check "  ...and does nothing" none_created

echo "== commits that don't call for a release"
commit -m "docs: words" >/dev/null
docs=$(commit -m "ci: a pipeline")
check "exits 0" release "$docs"
check "  ...without a tag" tags "v0.1.0 "
check "  ...a commit" main_is "$docs"
check "  ...or a release" none_created

echo "== a fix, then a breaking change"
check "fix: exits 0" release "$(commit -m "fix: another fix")"
check "  ...tags v0.1.1" tags "v0.1.0 v0.1.1 "
check "  ...links the diff from v0.1.0" notes_have v0.1.1 "**Full diff**: https://github.example/owner/envsetup/compare/v0.1.0...v0.1.1"
check "feat!: exits 0" release "$(commit -m "feat(work)!: break it")"
check "  ...tags v0.2.0" tags "v0.1.0 v0.1.1 v0.2.0 "

echo "== main moves on while a release runs"
x=$(commit -m "feat: x")
y=$(commit -m "fix: y")
check "the older commit's run exits 0" release "$x"
check "  ...warns" grep -qF "::warning::main moved on" "$T/out"
check "  ...and pushes nothing" tags "v0.1.0 v0.1.1 v0.2.0 "
check "  ...leaving main where it was" main_is "$y"
check "the newer commit's run exits 0" release "$y"
check "  ...and releases both" tags "v0.1.0 v0.1.1 v0.2.0 v0.3.0 "
check "  ...in one entry" [ "$(section v0.3.0 Features)/$(section v0.3.0 Fixes)" = "- x/- y" ]
check "re-running the older commit exits 0" release "$x"
check "  ...and does nothing (v0.3.0 has it)" none_created

echo "== the push is refused (as branch protection would)"
z=$(commit -m "fix: z")
printf '#!/bin/sh\necho "protected branch" >&2\nexit 1\n' >"$O/hooks/pre-receive"
chmod +x "$O/hooks/pre-receive"
check "fails" fails release "$z"
check "  ...pushing neither the commit nor the tag" tags "v0.1.0 v0.1.1 v0.2.0 v0.3.0 "
check "  ...nor publishing a release" none_created
rm "$O/hooks/pre-receive"
check "once it's allowed, a re-run releases it" release "$z"
check "  ...as v0.3.1" tags "v0.1.0 v0.1.1 v0.2.0 v0.3.0 v0.3.1 "

echo "== usage"
check "an unknown step is refused" [ "$(cd "$T/ci" && GITHUB_SHA=x "$root/.github/scripts/release.sh" nope >/dev/null 2>&1; echo $?)" = 2 ]

echo
if ((failures)); then
	echo "$failures check(s) failed"
	exit 1
fi
echo "all checks passed"
