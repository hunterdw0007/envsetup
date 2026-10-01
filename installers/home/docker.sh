#!/usr/bin/env bash
# Installs Docker if it isn't already on PATH. An installer rather than a package-list
# entry because the package differs per distro (RHEL clones don't ship one at all), and
# a Docker CE or Docker Desktop that's already installed must be left alone.
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
		# RHEL and its clones ship podman, not docker: use Docker CE's own repo.
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
	echo "Not installing Docker with ${manager:-no package manager}: use Docker Desktop, or virtualisation.docker on NixOS."
	exit 0
	;;
esac
envsetup::pkg_install "$manager" "${pkgs[@]}"
echo "Docker installed. If it isn't running yet: sudo systemctl enable --now docker"
