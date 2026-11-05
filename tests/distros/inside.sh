#!/bin/sh
# This script runs as root inside one distro container, which run.sh starts.
# It adds what a real machine already has: bash, sudo and a user who is not root.
# Then it runs scenarios.sh.
# It is a POSIX sh script, because some images (Alpine) have no bash yet.
set -eu

# This is an optional hook for the local network (proxy, CA, mirrors).
# run.sh mounts it from DISTROS_PREHOOK.
# shellcheck source=/dev/null
[ -f /prehook.sh ] && . /prehook.sh

# A real machine already has its timezone and other settings.
# Without them, a bare image would stop and ask.
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
