#!/usr/bin/env bash
# This script opens or updates the one PR that bumps installers/versions.txt.
# It runs after bump-versions.sh writes that file in this checkout of main.
# Then it starts the distros workflow on the PR's branch.
# That workflow installs the work profile's tools from the new pins.
#
#   bump-pr.sh <changes.md>   the list that bump-versions.sh printed
#
# .github/workflows/bump-versions.yml runs this script every week.
# .github/workflows/drop-eol-distros.yml runs it every month for tests/distros/run.sh.
# That workflow sets these variables:
#   BUMP_BRANCH  the PR's branch (default: bump-versions)
#   BUMP_FILE    the file that the PR changes (default: installers/versions.txt)
#   BUMP_TITLE   the PR's title and the commit's first line
#   BUMP_BODY    a file with the PR's description, instead of the text below
# PUSH_TOKEN and GH_TOKEN must not be GITHUB_TOKEN.
# A push or PR made with GITHUB_TOKEN starts no workflows, so the PR would get no CI.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
changes=${1:?the list of changes bump-versions.sh printed}
repo=${GITHUB_REPOSITORY:?owner/repo, as GitHub Actions sets it}
server=${GITHUB_SERVER_URL:-https://github.com}
branch=${BUMP_BRANCH:-bump-versions}
file=${BUMP_FILE:-installers/versions.txt}
title=${BUMP_TITLE:-"fix(installers): bump pinned tool versions"}

if git diff --quiet -- "$file"; then
	echo "$file has no changes."
	exit 0
fi
# The git config goes through the environment, so the token is in no file and no argument.
# Hooks are off.
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null
if [[ -n "${PUSH_TOKEN:-}" ]]; then
	export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_1="http.$server/.extraheader"
	GIT_CONFIG_VALUE_1="AUTHORIZATION: basic $(printf 'x-access-token:%s' "$PUSH_TOKEN" | base64 -w0)"
	export GIT_CONFIG_VALUE_1
fi
# The PR may already have this change.
# Then a push of the same change would only run CI again.
if git fetch -q origin "refs/heads/$branch" 2>/dev/null && git diff --quiet FETCH_HEAD -- "$file"; then
	echo "$branch already has this change to $file."
	exit 0
fi

git add "$file"
git -c user.name='github-actions[bot]' -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
	commit -q -F - <<EOF
$title

$(<"$changes")
EOF
# Each week the branch gets a new commit on top of main, so it never falls behind main.
# This push replaces anything that someone pushed to the branch by hand.
git push -q --force origin "HEAD:refs/heads/$branch"

body=$(mktemp)
trap 'rm -f "$body"' EXIT
if [[ -n "${BUMP_BODY:-}" ]]; then
	cp "$BUMP_BODY" "$body"
else
	cat >"$body" <<EOF
This is the weekly bump of \`installers/versions.txt\`, from \`.github/scripts/bump-versions.sh\`.
It has the newest release of each tool.
It also has the sha256 that each project publishes for each download.

$(<"$changes")

## Test plan
- [ ] CI passes. The smoke test checks that every pinned name has a line and hashes.
- [ ] The [distros run on \`$branch\`]($server/$repo/actions/workflows/distros.yml?query=branch%3A$branch) installed the work profile's tools from these pins on every distro. The tools are kubectl, helm, gh, terraform and awscli.
- [ ] I read the release notes of each new major version. I checked for changes that break how people use the tool. The distros run does not cover the extras (k9s, lazygit, mise, starship, uv, yq).

The script writes this PR again each week while it is open. It replaces any edits pushed to \`$branch\`.
EOF
fi
if [[ -n "$(gh pr list --repo "$repo" --head "$branch" --state open --json number --jq '.[].number')" ]]; then
	gh pr edit "$branch" --repo "$repo" --body-file "$body"
else
	gh pr create --repo "$repo" --base main --head "$branch" --title "$title" --body-file "$body"
fi
if ! gh workflow run distros.yml --repo "$repo" --ref "$branch"; then
	echo "::warning::Couldn't start the distros workflow on $branch. Check that the token has Actions: write. Then start the workflow by hand."
fi
