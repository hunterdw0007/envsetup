# shellcheck shell=bash
# Functions for the work profile only.

# resetNode rebuilds the dependencies of a helm chart from the start.
# Run it in the chart's folder.
# It stops if the folder has no Chart.yaml.
# So it cannot delete a charts/ folder somewhere else.
resetNode() {
	if [[ ! -f Chart.yaml ]]; then
		echo "resetNode: $PWD has no Chart.yaml, so it is not a helm chart. Nothing was deleted." >&2
		return 1
	fi
	rm -rfv charts/ Chart.lock
	helm dependency build
}
