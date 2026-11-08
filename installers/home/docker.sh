#!/usr/bin/env bash
# This script installs Docker if it is not already on PATH.
# Docker needs an installer, not a line in a package list.
# The package differs for each distro, and RHEL-like systems do not ship one at all.
# The script must also leave an installed Docker CE or Docker Desktop alone.
set -euo pipefail

source "$ENVSETUP_ROOT/lib/common.sh"

envsetup::has_cmd docker && exit 0

manager="$(envsetup::pkg_manager)"
id="$(envsetup::os_release ID)"
case $manager in
apt) pkgs=(docker.io) ;;
dnf)
	case $id in
	fedora) pkgs=(moby-engine) ;;
	amzn) pkgs=(docker) ;;
	*)
		# RHEL-like systems ship podman, not docker.
		# So this uses Docker CE's own repo.
		# This script writes the repo file, so nothing unchecked runs as root.
		# dnf checks each package against Docker's key in docker.asc.
		# Docker publishes the key's fingerprint at https://docs.docker.com/engine/install/rhel/:
		# 060A 61C5 1B55 8A7F 742B 77AA C52F EB6B 621E 9F35
		# If Docker changes its key, replace docker.asc with https://download.docker.com/linux/centos/gpg.
		# Then copy the new fingerprint from that page into this comment.
		repo=centos
		[[ "$id" == rhel ]] && repo=rhel
		envsetup::as_root rpm --import "$ENVSETUP_ROOT/installers/home/docker.asc"
		# shellcheck disable=SC2016 # dnf, not bash, expands $basearch and $releasever
		printf '[docker-ce-stable]\nname=Docker CE Stable - $basearch\nbaseurl=https://download.docker.com/linux/%s/$releasever/$basearch/stable\nenabled=1\ngpgcheck=1\n' "$repo" |
			envsetup::as_root tee /etc/yum.repos.d/docker-ce.repo >/dev/null
		pkgs=(docker-ce docker-ce-cli containerd.io)
		;;
	esac
	;;
zypper | pacman | apk) pkgs=(docker) ;;
*)
	echo "Not installing Docker with ${manager:-no package manager}. Use Docker Desktop, or virtualisation.docker on NixOS."
	exit 0
	;;
esac
envsetup::pkg_install "$manager" "${pkgs[@]}"
echo "Docker is installed. If it is not running yet, run: sudo systemctl enable --now docker"
