#!/bin/sh
# Runs as root inside one distro container (started by run.sh). Gives the box what a
# real machine already has (bash, sudo, a non-root user), then hands off to
# scenarios.sh. POSIX sh: some images (Alpine) have no bash yet.
set -eu

# Optional site hook (proxy, CA, mirrors), mounted by run.sh from DISTROS_PREHOOK.
# shellcheck source=/dev/null
[ -f /prehook.sh ] && . /prehook.sh

# A real machine already has its timezone etc. configured; a bare image would stop to ask.
export DEBIAN_FRONTEND=noninteractive

for pm in apt-get dnf zypper pacman apk; do
	command -v "$pm" >/dev/null 2>&1 && break
	pm=
done
echo "== bootstrap with ${pm:-nothing}"
case $pm in
apt-get)
	apt-get update -qq && apt-get install -y -qq bash sudo passwd ca-certificates >/dev/null
	;;
dnf) dnf install -y -q bash sudo shadow-utils >/dev/null ;;
zypper) zypper -n -q install bash sudo shadow >/dev/null ;;
pacman) pacman -Sy --noconfirm --needed bash sudo >/dev/null ;;
apk) apk add -q bash sudo shadow ;;
*)
	echo "no supported package manager in this image" >&2
	exit 1
	;;
esac
exec bash /src/tests/distros/scenarios.sh "$pm"
