#!/usr/bin/env bash
# Opens, or refreshes, the one PR that bumps installers/versions.txt, once
# bump-versions.sh has rewritten it in this checkout of main. Then starts the distros
# workflow on that branch, which installs the work profile's tools from the new pins.
#
#   bump-pr.sh <changes.md>   the list bump-versions.sh printed
#
# Run weekly by .github/workflows/bump-versions.yml. Needs PUSH_TOKEN and GH_TOKEN that
# aren't GITHUB_TOKEN: a push or PR made with GITHUB_TOKEN starts no workflows, so the
# PR would get no CI.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
changes=${1:?the list of changes bump-versions.sh printed}
repo=${GITHUB_REPOSITORY:?owner/repo, as GitHub Actions sets it}
server=${GITHUB_SERVER_URL:-https://github.com}
branch=${BUMP_BRANCH:-bump-versions}
title="fix(installers): bump pinned tool versions"

if git diff --quiet -- installers/versions.txt; then
	echo "Every pin is current."
	exit 0
fi
# Git config through the environment, so the token is in no file or argv; hooks off.
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null
if [[ -n "${PUSH_TOKEN:-}" ]]; then
	export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_1="http.$server/.extraheader"
	GIT_CONFIG_VALUE_1="AUTHORIZATION: basic $(printf 'x-access-token:%s' "$PUSH_TOKEN" | base64 -w0)"
	export GIT_CONFIG_VALUE_1
fi
# Already proposed: pushing the same pins again would only re-run CI.
if git fetch -q origin "refs/heads/$branch" 2>/dev/null && git diff --quiet FETCH_HEAD -- installers/versions.txt; then
	echo "$branch already has these pins."
	exit 0
fi

git add installers/versions.txt
git -c user.name='github-actions[bot]' -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
	commit -q -F - <<EOF
$title

$(<"$changes")
EOF
# A fresh commit on main each week, so the branch never goes stale against it. This
# replaces anything pushed to the branch by hand.
git push -q --force origin "HEAD:refs/heads/$branch"

body=$(mktemp)
trap 'rm -f "$body"' EXIT
cat >"$body" <<EOF
Weekly bump of \`installers/versions.txt\`, from \`.github/scripts/bump-versions.sh\`: the newest release of each tool and the sha256 its project publishes for each download.

$(<"$changes")

## Test plan
- [ ] CI passes (the smoke test checks every pinned name has a line and hashes).
- [ ] The [distros run on \`$branch\`]($server/$repo/actions/workflows/distros.yml?query=branch%3A$branch) installed the work profile's tools (kubectl, helm, gh, terraform, awscli) from these pins on every distro.
- [ ] Release notes of any major version bump read, for changes that break how people use the tool. The extras (k9s, lazygit, mise, starship, uv, yq) aren't in the distros run.

This PR is rewritten each week while it's open; edits pushed to \`$branch\` are replaced.
EOF
if [[ -n "$(gh pr list --repo "$repo" --head "$branch" --state open --json number --jq '.[].number')" ]]; then
	gh pr edit "$branch" --repo "$repo" --body-file "$body"
else
	gh pr create --repo "$repo" --base main --head "$branch" --title "$title" --body-file "$body"
fi
if ! gh workflow run distros.yml --repo "$repo" --ref "$branch"; then
	echo "::warning::Couldn't start the distros workflow on $branch (does the token have Actions: write?). Start it by hand."
fi
