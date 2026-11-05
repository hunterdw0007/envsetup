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
		repo=centos
		[[ "$id" == rhel ]] && repo=rhel
		tmp="$(mktemp -d)"
		trap 'rm -rf "$tmp"' EXIT
		curl -fsSL -o "$tmp/docker-ce.repo" "https://download.docker.com/linux/$repo/docker-ce.repo"
		envsetup::as_root install -m 0644 "$tmp/docker-ce.repo" /etc/yum.repos.d/docker-ce.repo
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
