#!/usr/bin/env bash
# Tries envsetup on real distros, each in a fresh container, with real package installs
# and downloads, and writes a Markdown report of what broke. Too slow for CI (minutes
# per distro, mostly downloads): run it by hand before handing out a build, or from the
# "distros" workflow, which only runs when triggered manually.
#
#   tests/distros/run.sh                              # every distro below, 3 at a time
#   tests/distros/run.sh fedora:latest alpine:latest  # just these
#   JOBS=6 DISTROS_SKIP="terraform awscli" tests/distros/run.sh
#
# Tests the commit checked out here, so commit first. Needs docker and network access.
#   DISTROS_OUT      where reports go (default: ./distros-report/<timestamp>)
#   DISTROS_SKIP     packages/installers to leave out, as in ENVSETUP_SKIP
#   DISTROS_PREHOOK  a sh script sourced first in every container (proxy, CA, mirrors);
#                    it can export DISTROS_KEEP_ENV="VAR ..." to keep those across sudo
#   DISTROS_DOCKER_ARGS  extra `docker run` arguments, e.g. "--network host"
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
images=("$@")
if ((${#images[@]} == 0)); then
	images=(
		# Most home desktops, WSL's default, and most VMs/cloud images
		ubuntu:24.04 ubuntu:22.04 debian:13 debian:12 linuxmintd/mint22-amd64
		# Fedora, and the RHEL family most work servers run
		fedora:latest almalinux:9 rockylinux/rockylinux:9 amazonlinux:2023
		# Arch and the fast-growing Arch-based desktops
		archlinux:latest
		# Not supported yet: shows what breaks
		opensuse/tumbleweed opensuse/leap:15.6 alpine:latest
	)
fi
out=${DISTROS_OUT:-$PWD/distros-report/$(date +%Y%m%d-%H%M%S)}
mkdir -p "$out"
read -ra docker_args <<<"${DISTROS_DOCKER_ARGS:-}"
prehook=()
[[ -n "${DISTROS_PREHOOK:-}" ]] && prehook=(-v "$(realpath "$DISTROS_PREHOOK"):/prehook.sh:ro")

run_one() {
	local image=$1 slug=${1//[\/:]/-} rc=0 err
	mkdir -p "$out/$slug"
	# Registries rate-limit anonymous pulls (Docker Hub answers 429); that's not a distro
	# problem, so it's reported apart. A mirror of the same image avoids it, e.g.
	# public.ecr.aws/docker/library/debian:13 for debian:13.
	for try in 1 2 3; do
		docker image inspect "$image" >/dev/null 2>&1 || docker pull -q "$image" >"$out/$slug/pull.log" 2>&1 && break
		((try < 3)) && sleep 30
	done
	if ! docker image inspect "$image" >/dev/null 2>&1; then
		# Registry errors can embed a signed URL kilobytes long; the log keeps it whole.
		err=$(tail -n 1 "$out/$slug/pull.log")
		[[ "$err" =~ https?://[^\ ]{60,} ]] && err=${err//"${BASH_REMATCH[0]}"/<url>}
		printf '%s\tcontainer\tWARN\tcouldn'"'"'t pull the image, so nothing ran: %s\n' "$slug" "${err:0:200}" >"$out/$slug/summary.tsv"
		echo "skipped  $image (pull failed)"
		return
	fi
	echo "started  $image"
	timeout "${DISTROS_TIMEOUT:-3600}" docker run --rm -t "${docker_args[@]}" "${prehook[@]}" \
		-e "DISTRO_SLUG=$slug" -e "DISTROS_SKIP=${DISTROS_SKIP:-}" \
		-v "$root:/src:ro" -v "$out:/report" \
		"$image" sh /src/tests/distros/inside.sh >"$out/$slug/container.log" 2>&1 || rc=$?
	if [[ ! -s "$out/$slug/summary.tsv" ]]; then
		printf '%s\tcontainer\tFAIL\texited %s before any test ran; see %s/container.log\n' \
			"$slug" "$rc" "$slug" >>"$out/$slug/summary.tsv"
	elif ((rc)); then
		printf '%s\tcontainer\tFAIL\texited %s; see %s/container.log\n' "$slug" "$rc" "$slug" >>"$out/$slug/summary.tsv"
	fi
	echo "finished $image"
}

for image in "${images[@]}"; do
	while (($(jobs -rp | wc -l) >= ${JOBS:-3})); do wait -n || true; done
	run_one "$image" &
done
wait

# One row per distro: each column is the worst result of that phase and its sub-checks.
cols=(bootstrap gum home work-full work-lite)
icon() { case $1 in PASS) echo "✅" ;; WARN) echo "⚠️" ;; FAIL) echo "❌" ;; *) echo "–" ;; esac; }
{
	echo "# envsetup on other distros"
	echo
	echo "Commit \`$(git -C "$root" rev-parse --short HEAD)\`, $(date -u '+%Y-%m-%d %H:%M UTC'). Logs are next to this file."
	echo
	printf '| distro |'
	printf ' %s |' "${cols[@]}"
	printf '\n|---|'
	printf -- '---|%.0s' "${cols[@]}"
	echo
	for image in "${images[@]}"; do
		slug=${image//[\/:]/-}
		printf "| \`%s\` |" "$image"
		for col in "${cols[@]}"; do
			worst=
			while IFS=$'\t' read -r _ phase status _; do
				[[ "$phase" == "$col" || "$phase" == "$col: "* || ("$phase" == container && "$col" == bootstrap) ]] || continue
				case "$status:$worst" in FAIL:* | WARN:PASS | WARN: | PASS:) worst=$status ;; esac
			done <"$out/$slug/summary.tsv"
			printf ' %s |' "$(icon "$worst")"
		done
		echo
	done
	echo
	echo "## Problems"
	echo
	found=0
	for image in "${images[@]}"; do
		slug=${image//[\/:]/-}
		while IFS=$'\t' read -r _ phase status detail; do
			[[ "$status" == PASS ]] && continue
			echo "- \`$image\` **$phase** ($status): $detail"
			found=1
		done <"$out/$slug/summary.tsv"
	done
	((found)) || echo "None."
} >"$out/report.md"

echo
cat "$out/report.md"
echo
echo "Report: $out/report.md"
! grep -q $'\tFAIL\t' "$out"/*/summary.tsv
