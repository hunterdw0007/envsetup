# shellcheck shell=bash
# Work-only functions.

# Rebuilds the dependencies of a helm chart from scratch. Run it in the directory of the
# chart. It stops if there is no Chart.yaml, so it cannot delete a charts/ dir elsewhere.
resetNode() {
	if [[ ! -f Chart.yaml ]]; then
		echo "resetNode: $PWD has no Chart.yaml, so it is not a helm chart. Nothing was deleted." >&2
		return 1
	fi
	rm -rfv charts/ Chart.lock
	helm dependency build
}
