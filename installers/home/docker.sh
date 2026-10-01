#!/usr/bin/env bash
# Installs Docker from the distro's own packages, unless some docker is already there.
# Not in packages/home.txt: on a machine with Docker CE (download.docker.com), the
# distro's docker.io needs containerd, which conflicts with Docker CE's containerd.io.
set -euo pipefail

source "$ENVSETUP_ROOT/lib/common.sh"

envsetup::has_cmd docker && exit 0

manager="$(envsetup::pkg_manager)"
case "$manager" in
apt) envsetup::pkg_install apt docker.io ;;
dnf) envsetup::pkg_install dnf moby-engine ;;
pacman) envsetup::pkg_install pacman docker ;;
*) echo "No distro package for Docker here; see https://docs.docker.com/engine/install/" >&2 ;;
esac
