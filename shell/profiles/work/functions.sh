# shellcheck shell=bash
# Work-only functions.

# Rebuilds a helm chart's dependencies from scratch (run from the chart's directory).
resetNode() {
	rm -rfv charts/ Chart.lock
	helm dependency build
}
