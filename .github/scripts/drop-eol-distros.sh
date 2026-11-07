#!/usr/bin/env bash
# This script removes each distro release whose security support has ended from tests/distros/run.sh.
# It reads each date from endoflife.date.
# README.md ("Supported systems") states the rule.
# .github/workflows/drop-eol-distros.yml runs this script every month and opens a PR (bump-pr.sh).
#
#   .github/scripts/drop-eol-distros.sh
#
# The script prints the removed releases as a Markdown list.
# A human then fixes each doc that the list names.
# Every image in the default list needs a row in the table below.
# A missing row or a failed lookup stops the script before the file changes.
#   EOL_TODAY  the date to compare with, as YYYY-MM-DD (default: today, in UTC)
#   EOL_API    the endoflife.date API (default: https://endoflife.date/api)
# The script needs curl, jq and git.
set -euo pipefail

root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
list=$root/tests/distros/run.sh
today=${EOL_TODAY:-$(date -u +%F)}
api=${EOL_API:-https://endoflife.date/api}

# Each row is: image, endoflife.date product, cycle, field, the name that docs use.
# The field is the JSON field that holds the end of security support.
# Its meaning differs for each product, so each row names the column title on the product's page.
# A rolling distro has no end date, so its product is "-".
declare -A rows=()
while read -r image product cycle field name; do
	[[ -z "$image" || "$image" == \#* ]] || rows[$image]="$product $cycle $field $name"
done <<'EOF'
# eol is "Maintenance & Security Support". extendedSupport is Ubuntu Pro ESM.
ubuntu:26.04 ubuntu 26.04 eol Ubuntu 26.04
ubuntu:24.04 ubuntu 24.04 eol Ubuntu 24.04
ubuntu:22.04 ubuntu 22.04 eol Ubuntu 22.04
# support is "Debian Security Support". eol is Debian LTS.
debian:13 debian 13 support Debian 13
debian:12 debian 12 support Debian 12
# eol is "Security Support". Mint ends a release when Ubuntu's ESM starts.
linuxmintd/mint22-amd64 linuxmint 22 eol Linux Mint 22
# support is "Active Support". eol is "Security Support".
almalinux:9 almalinux 9 eol AlmaLinux 9
rockylinux/rockylinux:9 rocky-linux 9 eol Rocky Linux 9
# support is "Standard Support". eol is "Security Support".
amazonlinux:2023 amazon-linux 2023 eol Amazon Linux 2023
# eol is "End of Life". The page defines support as security updates.
opensuse/leap:15.6 opensuse 15.6 eol openSUSE Leap 15.6
fedora:latest -
archlinux:latest -
opensuse/tumbleweed -
alpine:latest -
EOF

# The default list sits between "	images=(" and "	)" in run.sh.
# The script writes the new run.sh to a temporary file first.
# So a failure leaves run.sh unchanged.
new=$(mktemp)
trap 'rm -f "$new"' EXIT
dropped=() in_list=false found=0
while IFS= read -r line; do
	if [[ "$line" == $'\timages=(' ]]; then
		in_list=true
	elif [[ "$line" == $'\t)' ]]; then
		in_list=false
	elif "$in_list"; then
		# The images come before any "#". A comment after them stays.
		images=${line%%#*} comment=${line:${#images}}
		read -ra words <<<"$images"
		# A blank line or a whole comment line stays as it is.
		if ((${#words[@]} == 0)); then
			printf '%s\n' "$line" >>"$new"
			continue
		fi
		kept=()
		for image in "${words[@]}"; do
			found=$((found + 1))
			[[ -v "rows[$image]" ]] || {
				echo "error: $image has no row in the table in $0. Add one." >&2
				exit 1
			}
			read -r product cycle field name <<<"${rows[$image]}"
			if [[ "$product" == - ]]; then
				kept+=("$image")
				continue
			fi
			date=$(curl -fsSL "$api/$product/$cycle.json" | jq -r ".$field")
			[[ "$date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || {
				echo "error: $api/$product/$cycle.json has no date in $field: $date" >&2
				exit 1
			}
			if [[ "$date" < "$today" ]]; then
				dropped+=("$image|$date|$product|$cycle|$name")
			else
				kept+=("$image")
			fi
		done
		# A line with no images left goes away.
		((${#kept[@]} == 0)) && continue
		line=$'\t\t'"${kept[*]}${comment:+ $comment}"
	fi
	printf '%s\n' "$line" >>"$new"
done <"$list"
((found > 0)) || {
	echo "error: found no default image list in $list." >&2
	exit 1
}

if ((${#dropped[@]} == 0)); then
	echo "Every distro release in tests/distros/run.sh still has security support on $today."
	exit 0
fi
cat "$new" >"$list"
echo "These distro releases lost security support before $today, so tests/distros/run.sh drops them:"
echo
for row in "${dropped[@]}"; do
	IFS='|' read -r image date product cycle name <<<"$row"
	echo "- \`$image\` ($name): security support ended on $date ([endoflife.date](https://endoflife.date/$product))."
	# CHANGELOG.md keeps its history.
	# The table above and the test's fixed data name releases on purpose.
	refs=$(git -C "$root" grep -n -F -e "$image" -e "$name" -- . ':!CHANGELOG.md' ':!.github/scripts/drop-eol-distros.sh' ':!tests/eol.sh' || true)
	if [[ -n "$refs" ]]; then
		echo "  Fix these lines by hand:"
		while IFS= read -r ref; do echo "  - \`${ref//\`/}\`"; done <<<"$refs"
	fi
done
