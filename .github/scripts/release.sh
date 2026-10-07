#!/usr/bin/env bash
# Releases main's HEAD when the commits since the last release call for a new version:
# commitizen reads them as Conventional Commits (see .cz.toml and "Releases" in
# AGENTS.md), `cz bump` adds their entry to CHANGELOG.md and commits and tags it vX.Y.Z,
# both are pushed to main, and a GitHub release is published with that entry as notes.
#
# Run by CI (.github/workflows/ci.yml) once main's checks pass, from a checkout of the
# pushed commit with full history and tags, commitizen and gh installed, and a token
# that can push to main and create releases. Safe to re-run: if HEAD is already in a
# release, only that release's GitHub page is created, if it's missing.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)" # cz reads .cz.toml and the template from here
repo=${GITHUB_REPOSITORY:?owner/repo, as GitHub Actions sets it}
server=${GITHUB_SERVER_URL:-https://github.com}
export GIT_AUTHOR_NAME='github-actions[bot]' GIT_COMMITTER_NAME='github-actions[bot]'
export GIT_AUTHOR_EMAIL='41898282+github-actions[bot]@users.noreply.github.com'
export GIT_COMMITTER_EMAIL=$GIT_AUTHOR_EMAIL

# envsetup::notes <tag>: the tag's CHANGELOG.md entry, without its "## vX.Y.Z (date)" heading.
envsetup::notes() {
	local line inside=0
	while IFS= read -r line; do
		if [[ "$line" == "## "* ]]; then
			if ((inside)); then break; fi
			if [[ "$line" == "## $1 "* || "$line" == "## $1" ]]; then inside=1; fi
		elif ((inside)); then
			printf '%s\n' "$line"
		fi
	done < <(git show "$1:CHANGELOG.md")
}

# The oldest release that includes HEAD: one this commit's earlier run made (the tag is
# on its bump commit, just after it), or a newer commit's.
tag=
read -r tag < <(git tag --contains HEAD --list 'v[0-9]*' --sort=v:refname) || true
if [[ -z "$tag" ]]; then
	base=$(git rev-parse HEAD)
	rc=0
	cz bump --yes --git-output-to-stderr || rc=$?
	if ((rc == 21)); then # commitizen's NO_INCREMENT
		echo "No commits since the last release call for a new version; nothing to release."
		exit 0
	fi
	((rc == 0)) || exit "$rc"
	tag=$(git describe --tags --exact-match --match 'v[0-9]*')
	# Atomic: main gets the bump commit and its tag together, or neither.
	if ! git push --atomic origin HEAD:refs/heads/main "refs/tags/$tag"; then
		git fetch -q origin main
		if [[ "$(git rev-parse FETCH_HEAD)" != "$base" ]]; then
			echo "::warning::main moved on while this ran, so $tag wasn't pushed. The next commit on main to pass CI releases these commits too."
			exit 0
		fi
		exit 1
	fi
	echo "Pushed $tag."
fi

if gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then
	echo "$tag is already released."
	exit 0
fi

body=$(mktemp)
trap 'rm -f "$body"' EXIT
{
	envsetup::notes "$tag"
	cat <<NOTES
### Install this version

\`\`\`sh
curl -fsSL https://raw.githubusercontent.com/$repo/main/install.sh | ENVSETUP_VERSION=$tag bash
\`\`\`

The same line switches an existing checkout to $tag. Leave out \`ENVSETUP_VERSION\` for the newest release.
NOTES
	if prev=$(git describe --tags --abbrev=0 --match 'v[0-9]*' "$tag^" 2>/dev/null); then
		printf '\n**Full diff**: %s/%s/compare/%s...%s\n' "$server" "$repo" "$prev" "$tag"
	fi
} >"$body"
gh release create "$tag" --repo "$repo" --verify-tag --title "$tag" --notes-file "$body"
