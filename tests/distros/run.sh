#!/usr/bin/env bash
# This script tests envsetup on real distros, each in a new container.
# It uses real package installs and downloads.
# It writes a Markdown report of what broke.
# It is too slow for CI, because each distro takes minutes, mostly for downloads.
# Run it by hand before you give a build to testers.
# Or run it from the "distros" workflow.
#
#   tests/distros/run.sh                              # every distro below, 3 at a time
#   tests/distros/run.sh fedora:latest alpine:latest  # just these
#   JOBS=6 DISTROS_SKIP="terraform awscli" tests/distros/run.sh
#
# The script tests the commit that is checked out here, so commit first.
# It needs docker and network access.
#   DISTROS_OUT      where reports go (default: ./distros-report/<timestamp>)
#   DISTROS_SKIP     packages and installers to skip, as in ENVSETUP_SKIP
#   DISTROS_PREHOOK  a sh script that every container sources first (proxy, CA, mirrors);
#                    it can export DISTROS_KEEP_ENV="VAR ..." so sudo keeps those variables
#   DISTROS_DOCKER_ARGS  extra `docker run` arguments, e.g. "--network host"
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
images=("$@")
if ((${#images[@]} == 0)); then
	images=(
		# Most home desktops, WSL's default, and most VMs/cloud images
		ubuntu:26.04 ubuntu:24.04 ubuntu:22.04 debian:13 linuxmintd/mint22-amd64
		# Fedora, and the RHEL family that most work servers run
		fedora:latest almalinux:9 rockylinux/rockylinux:9 amazonlinux:2023
		# Arch, and the desktops based on Arch, which are growing fast
		archlinux:latest
		# Not supported yet, so this shows what breaks
		opensuse/tumbleweed opensuse/leap:16.0 alpine:latest
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
	# A reused DISTROS_OUT holds the old results, so remove them first.
	rm -f "$out/$slug/summary.tsv" "$out/$slug/host.tsv" "$out/$slug/container.log"
	# Registries limit the number of anonymous pulls, and Docker Hub then answers 429.
	# That is not a problem with the distro, so the report lists it separately.
	# A mirror of the same image avoids the limit.
	# For example, use public.ecr.aws/docker/library/debian:13 for debian:13.
	for try in 1 2 3; do
		docker image inspect "$image" >/dev/null 2>&1 || docker pull -q "$image" >"$out/$slug/pull.log" 2>&1 && break
		((try < 3)) && sleep 30
	done
	if ! docker image inspect "$image" >/dev/null 2>&1; then
		# A registry error can include a signed URL that is kilobytes long.
		# The log keeps the whole URL.
		err=$(tail -n 1 "$out/$slug/pull.log")
		[[ "$err" =~ https?://[^\ ]{60,} ]] && err=${err//"${BASH_REMATCH[0]}"/<url>}
		printf '%s\tcontainer\tWARN\tcouldn'"'"'t pull the image, so nothing ran: %s\n' "$slug" "${err:0:200}" >"$out/$slug/host.tsv"
		echo "skipped  $image (pull failed)"
		return
	fi
	echo "started  $image"
	timeout "${DISTROS_TIMEOUT:-3600}" docker run --rm -t "${docker_args[@]}" "${prehook[@]}" \
		-e "DISTRO_SLUG=$slug" -e "DISTROS_SKIP=${DISTROS_SKIP:-}" \
		-v "$root:/src:ro" -v "$out:/report" \
		"$image" sh /src/tests/distros/inside.sh >"$out/$slug/container.log" 2>&1 || rc=$?
	# With rootful Docker, root owns summary.tsv, so the host writes its own rows to host.tsv.
	if [[ ! -s "$out/$slug/summary.tsv" ]]; then
		printf '%s\tcontainer\tFAIL\texited %s before any test ran; see %s/container.log\n' \
			"$slug" "$rc" "$slug" >>"$out/$slug/host.tsv"
	elif ((rc)); then
		printf '%s\tcontainer\tFAIL\texited %s; see %s/container.log\n' "$slug" "$rc" "$slug" >>"$out/$slug/host.tsv"
	fi
	echo "finished $image"
}

pids=() bad=0
for image in "${images[@]}"; do
	while (($(jobs -rp | wc -l) >= ${JOBS:-3})); do wait -n || true; done
	run_one "$image" &
	pids+=("$!")
done
# bash keeps each job's exit status, even after wait -n.
# A job fails when set -e stops it, for example on a row that it cannot write.
for pid in "${pids[@]}"; do wait "$pid" || bad=1; done

# Each distro gets one column for each phase.
cols=(bootstrap gum home work-full work-lite)
# rows <slug> prints the rows of one distro: the container's, then the host's.
rows() { cat "$out/$1/summary.tsv" "$out/$1/host.tsv" 2>/dev/null || true; }
# in_col <phase> <col> tells whether a row of that phase counts in that column.
in_col() { [[ "$1" == "$2" || "$1" == "$2: "* || ("$1" == container && "$2" == bootstrap) ]]; }
# fail_row <slug> <phase> <detail> adds a FAIL row, and marks the run bad if it cannot.
# The run goes on, so the report still gets written.
fail_row() {
	printf '%s\t%s\tFAIL\t%s; see %s/container.log\n' "$1" "$2" "$3" "$1" >>"$out/$1/host.tsv" || bad=1
}

# A distro without a result for each phase counts as a failure, never as a pass.
# Only a container that ran must have every phase, because a failed pull writes a WARN row.
ran=0
for image in "${images[@]}"; do
	slug=${image//[\/:]/-}
	[[ -e "$out/$slug/container.log" ]] && ran=1
	if [[ -e "$out/$slug/summary.tsv" && ! -r "$out/$slug/summary.tsv" ]]; then
		fail_row "$slug" container "couldn't read summary.tsv"
	elif [[ -z "$(rows "$slug")" ]]; then
		fail_row "$slug" container "no results"
	elif [[ -e "$out/$slug/container.log" && "$(rows "$slug")" != *$'\tFAIL\t'* ]]; then
		for col in "${cols[@]}"; do
			while IFS=$'\t' read -r _ phase _; do
				in_col "$phase" "$col" && continue 2
			done < <(rows "$slug")
			fail_row "$slug" "$col" "no result"
		done
	fi
done

# The table has one row for each distro.
# Each column shows the worst result of that phase and its checks.
icon() { case $1 in PASS) echo "✅" ;; WARN) echo "⚠️" ;; FAIL) echo "❌" ;; *) echo "–" ;; esac }
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
				in_col "$phase" "$col" || continue
				case "$status:$worst" in FAIL:* | WARN:PASS | WARN: | PASS:) worst=$status ;; esac
			done < <(rows "$slug")
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
		done < <(rows "$slug")
	done
	if ((! ran)); then
		echo "- No image ran, so this run tested nothing. See each pull.log."
		found=1
	fi
	if ((bad)); then
		echo "- run.sh hit an error, so some results may be missing or old. See the output of run.sh."
		found=1
	fi
	((found)) || echo "None."
} >"$out/report.md"

echo
cat "$out/report.md"
echo
echo "Report: $out/report.md"
if ((bad || ! ran)); then exit 1; fi
all=$(for image in "${images[@]}"; do rows "${image//[\/:]/-}"; done)
[[ "$all" != *$'\tFAIL\t'* ]]
