#!/usr/bin/env bash
# Releases main's HEAD when the commits since the last release call for a new version
# (see .cz.toml and "Releases" in AGENTS.md). Two steps, so the push token is never in
# the checkout or in commitizen's process. That's defense in depth, not a boundary: later
# steps of a job inherit what earlier ones leave ($GITHUB_PATH, $GITHUB_ENV, the
# workspace). The control is commitizen's hash lock (.github/actions/commitizen).
#
#   release.sh bump     cz bump: a "bump:" commit adding the version's CHANGELOG.md entry,
#                       tagged vX.Y.Z, both only local. Needs commitizen, no token.
#   release.sh publish  pushes them to main atomically, then publishes a GitHub release
#                       with that entry as its notes. Needs PUSH_TOKEN (unless the remote
#                       needs none) and gh with GH_TOKEN; never runs cz.
#
# Run by CI (.github/workflows/ci.yml) once main's checks pass, from a checkout of the
# pushed commit ($GITHUB_SHA) with full history and tags; tests/release.sh runs it the
# same way. Safe to re-run: if that commit is already released, publish only creates
# its GitHub release, if it's missing.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)" # cz reads .cz.toml and the template from here
base=${GITHUB_SHA:?the commit CI checked out}
repo=${GITHUB_REPOSITORY:?owner/repo, as GitHub Actions sets it}
server=${GITHUB_SERVER_URL:-https://github.com}

# The oldest release that includes HEAD: this run's bump, an earlier run's for the same
# commit (the tag is on its bump commit, just after it), or a newer commit's.
envsetup::release_tag() {
	local tag=
	read -r tag < <(git tag --contains HEAD --list 'v[0-9]*' --sort=v:refname) || true
	echo "$tag"
}

# envsetup::notes <tag>: the tag's CHANGELOG.md entry, without its "## vX.Y.Z (date)"
# heading or the blank lines around it.
envsetup::notes() {
	local line inside=0 notes=
	while IFS= read -r line; do
		if [[ "$line" == "## "* ]]; then
			if ((inside)); then break; fi
			if [[ "$line" == "## $1 "* || "$line" == "## $1" ]]; then inside=1; fi
		elif ((inside)); then
			notes+=$line$'\n'
		fi
	done < <(git show "$1:CHANGELOG.md")
	while [[ "$notes" == $'\n'* ]]; do notes=${notes#$'\n'}; done
	while [[ "$notes" == *$'\n\n' ]]; do notes=${notes%$'\n'}; done
	printf '%s' "$notes"
}

envsetup::bump() {
	local rc=0 tag
	tag=$(envsetup::release_tag)
	if [[ -n "$tag" ]]; then
		echo "$tag already includes this commit."
		return 0
	fi
	export GIT_AUTHOR_NAME='github-actions[bot]' GIT_COMMITTER_NAME='github-actions[bot]'
	export GIT_AUTHOR_EMAIL='41898282+github-actions[bot]@users.noreply.github.com'
	export GIT_COMMITTER_EMAIL=$GIT_AUTHOR_EMAIL
	cz bump --yes --git-output-to-stderr || rc=$?
	if ((rc == 21)); then # commitizen's NO_INCREMENT
		echo "No commits since the last release call for a new version; nothing to release."
	elif ((rc != 0)); then
		return "$rc"
	fi
}

envsetup::publish() {
	local tag prev
	tag=$(envsetup::release_tag)
	if [[ -z "$tag" ]]; then
		echo "Nothing to release."
		return 0
	fi
	if [[ "$(git rev-parse HEAD)" != "$base" ]]; then # bump made a commit: push it
		# Git config through the environment, so the token is in no file or argv. Hooks off,
		# so one left in .git/hooks doesn't run with the token (defense in depth, as above).
		export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null
		if [[ -n "${PUSH_TOKEN:-}" ]]; then
			export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_1="http.$server/.extraheader"
			GIT_CONFIG_VALUE_1="AUTHORIZATION: basic $(printf 'x-access-token:%s' "$PUSH_TOKEN" | base64 -w0)"
			export GIT_CONFIG_VALUE_1
		fi
		# Atomic: main gets the bump commit and its tag together, or neither.
		if ! git push --atomic origin HEAD:refs/heads/main "refs/tags/$tag"; then
			git fetch -q origin main
			if [[ "$(git rev-parse FETCH_HEAD)" != "$base" ]]; then
				echo "::warning::main moved on while this ran, so $tag wasn't pushed. The next commit on main to pass CI releases these commits too."
				return 0
			fi
			return 1
		fi
		echo "Pushed $tag."
	fi

	if gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then
		echo "$tag is already released."
		return 0
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
}

case ${1:-} in
bump) envsetup::bump ;;
publish) envsetup::publish ;;
*)
	echo "Usage: $0 bump|publish" >&2
	exit 2
	;;
esac
