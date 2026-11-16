#!/usr/bin/env bash
# setup.sh runs envsetup from this clone.
# envsetup is a Go program (cmd/envsetup).
# It reads shell/, lib/, installers/ and packages/ from this clone.
# ./setup.sh --help lists the options.
set -euo pipefail

# This check runs first, so the old bash 3.2 on a Mac can parse it.
# A clone on a Mac stops here.
if [[ "$OSTYPE" != linux* ]]; then
	printf '%s\n' "envsetup supports Linux only." "v0.3.0 is the last release that supports macOS." \
		"To install v0.3.0, run: git fetch --tags && git checkout v0.3.0 && ./setup.sh" \
		"To uninstall envsetup, run: git fetch --tags && git checkout v0.3.0 && ./setup.sh --uninstall" >&2
	exit 1
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# ENVSETUP_BIN names a binary to run instead, for example in the tests.
# install.sh puts a release's binary in bin/.
# Otherwise this script builds bin/envsetup with Go.
# go build reuses its cache, so a second build takes well under a second.
bin=${ENVSETUP_BIN:-$root/bin/envsetup}
if [[ -z "${ENVSETUP_BIN:-}" ]] && command -v go &>/dev/null; then
	(cd "$root" && go build -trimpath -o bin/envsetup ./cmd/envsetup)
fi
if [[ ! -x "$bin" ]]; then
	echo "setup.sh needs Go to build envsetup from this clone: https://go.dev/doc/install" >&2
	echo "Or run the curl command from the README, which downloads a release." >&2
	exit 1
fi
ENVSETUP_FILES=$root exec "$bin" "$@"
