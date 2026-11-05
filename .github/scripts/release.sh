#!/usr/bin/env bash
# This script releases the HEAD of main when the commits since the last release need a new version.
# See .cz.toml and "Releases" in AGENTS.md.
# It has two steps, so the push token is never in the checkout or in commitizen's process.
# This adds a layer of protection, but it does not isolate the steps.
# Later steps of a job get what earlier steps leave ($GITHUB_PATH, $GITHUB_ENV, the workspace).
# The main protection is commitizen's hash lock (.github/actions/commitizen).
#
#   release.sh bump     runs cz bump: a local "bump:" commit adds the version's
#                       CHANGELOG.md entry, and a local vX.Y.Z tag marks it.
#                       Needs commitizen and no token.
#   release.sh publish  pushes the commit and the tag to main together. Then it
#                       publishes a GitHub release with the entry as its notes.
#                       Needs PUSH_TOKEN, unless the remote needs no token.
#                       Needs gh with GH_TOKEN. Never runs cz.
#
# CI (.github/workflows/ci.yml) runs this script after the checks on main pass.
# It runs from a checkout of the pushed commit ($GITHUB_SHA), with the full history and tags.
# tests/release.sh runs it the same way.
# You can run it again safely.
# If the commit already has a release, publish only creates the missing GitHub release.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)" # cz reads .cz.toml and the template from here
base=${GITHUB_SHA:?the commit CI checked out}
repo=${GITHUB_REPOSITORY:?owner/repo, as GitHub Actions sets it}
server=${GITHUB_SERVER_URL:-https://github.com}

# This function prints the oldest release that includes HEAD.
# That can be the bump of this run, or of an earlier run for the same commit.
# In that case the tag is on the bump commit, right after HEAD.
# It can also be the release of a newer commit.
envsetup::release_tag() {
	local tag=
	read -r tag < <(git tag --contains HEAD --list 'v[0-9]*' --sort=v:refname) || true
	echo "$tag"
}

# envsetup::notes <tag> prints the tag's CHANGELOG.md entry.
# It leaves out the "## vX.Y.Z (date)" heading and the blank lines around it.
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
		echo "No commit since the last release needs a new version. Nothing to release."
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
	if [[ "$(git rev-parse HEAD)" != "$base" ]]; then # bump made a commit, so push it
		# The git config goes through the environment, so the token is in no file and no argument.
		# Hooks are off, so a hook left in .git/hooks does not run with the token.
		# This adds a layer of protection, as above.
		export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null
		if [[ -n "${PUSH_TOKEN:-}" ]]; then
			export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_1="http.$server/.extraheader"
			GIT_CONFIG_VALUE_1="AUTHORIZATION: basic $(printf 'x-access-token:%s' "$PUSH_TOKEN" | base64 -w0)"
			export GIT_CONFIG_VALUE_1
		fi
		# The push is atomic: main gets the bump commit and its tag together, or gets neither.
		if ! git push --atomic origin HEAD:refs/heads/main "refs/tags/$tag"; then
			git fetch -q origin main
			if [[ "$(git rev-parse FETCH_HEAD)" != "$base" ]]; then
				echo "::warning::main got a new commit while this ran, so $tag was not pushed. The next commit on main that passes CI also releases these commits."
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

This command also switches a machine with another release to $tag. Leave out \`ENVSETUP_VERSION\` to get the newest release.
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
