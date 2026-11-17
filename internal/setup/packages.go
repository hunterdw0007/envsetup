package setup

import (
	"fmt"
	"regexp"
	"strings"

	"github.com/hunterdw0007/envsetup/internal/ui"
)

// InstallPackages installs the resolved packages with the package manager (envsetup::install_packages).
func (s *Setup) InstallPackages() error {
	if s.Lite() {
		s.Warn("work (lite) does not assume sudo, so it installs no packages.")
		return nil
	}
	manager := s.PkgManager()
	if manager == "" {
		s.Fail("No supported package manager found.")
		return ErrFailed
	}
	var names []string
	for _, pkg := range s.Cfg.ResolvedPackages {
		if name := s.PkgName(manager, pkg); name != "" {
			names = append(names, name)
		}
	}
	if len(names) == 0 {
		s.Warn("No packages listed for " + s.Cfg.Profile + ".")
		return nil
	}
	if manager == "dnf" {
		if err := s.enableEPEL(); err != nil {
			return err
		}
	}
	if s.DryRun {
		how := manager
		if manager != "brew" && manager != "nix" {
			how += " (as root)"
		}
		s.Would(fmt.Sprintf("install %d packages with %s, and skip the ones already installed: %s", len(names), how, strings.Join(names, " ")))
		return nil
	}
	s.UI.Print(ui.Step, "Installing with "+manager+": "+strings.Join(names, " "))
	return s.PkgInstall(manager, s.Cfg.ResolvedPackages...)
}

var rhelID = regexp.MustCompile(`^(rhel|ol)$`)

// enableEPEL asks before it adds EPEL (envsetup::enable_epel).
// RHEL and similar systems ship fewer packages.
// fzf, ripgrep, bat, htop, neovim and about ten more listed packages come from EPEL.
func (s *Setup) enableEPEL() error {
	guide := "To turn on EPEL yourself, see https://docs.fedoraproject.org/en-US/epel/getting-started/"
	id, _ := s.libOutput("envsetup::os_release", "ID")
	if !rhelID.MatchString(id) {
		if like, _ := s.libOutput("envsetup::os_release", "ID_LIKE"); !strings.Contains(" "+like+" ", " rhel ") {
			return nil
		}
	}
	if s.Quiet("rpm", "-q", "epel-release", "oracle-epel-release-el8", "oracle-epel-release-el9", "oracle-epel-release-el10") == nil {
		return nil
	}
	// RHEL's own repos have no epel-release.
	// envsetup does not install it from a URL, because the URL names no version.
	if id == "rhel" {
		s.Warn("EPEL is off. envsetup installs what the repos of RHEL have.", guide)
		return nil
	}
	if s.DryRun {
		s.Would("ask to turn on EPEL, Fedora's extra packages for " + id + ". About a third of the packages come from EPEL")
		return nil
	}
	if yes, _ := s.UI.Confirm("Turn on EPEL? EPEL is Fedora's extra package repo for "+id+". About a third of the packages come from it.", false); !yes {
		return nil
	}
	pkg := "epel-release"
	if id == "ol" {
		version, _ := s.libOutput("envsetup::os_release", "VERSION_ID")
		version, _, _ = strings.Cut(version, ".")
		pkg = "oracle-epel-release-el" + version
	}
	if s.AsRoot("dnf", "install", "-y", pkg) != nil {
		s.Warn("Couldn't turn on EPEL. envsetup installs what the repos of "+id+" have.", guide)
		return nil
	}
	// Some EPEL packages need the CodeReady Builder repo.
	// The epel-release package includes the helper that turns it on.
	if HasCmd("crb") {
		return s.AsRoot("crb", "enable")
	}
	return nil
}

// pkgInstalled reports whether the package manager has the package (envsetup::pkg_installed).
func (s *Setup) pkgInstalled(manager, name string) bool {
	switch manager {
	case "apt":
		return s.quietOutput("dpkg-query", "-W", "-f=${Status}", name) == "install ok installed"
	case "dnf", "zypper":
		return s.Quiet("rpm", "-q", "--whatprovides", name) == nil
	case "pacman":
		return s.Quiet("pacman", "-T", name) == nil
	case "apk":
		return s.Quiet("apk", "info", "-e", name) == nil
	case "brew":
		return s.Quiet("brew", "list", name) == nil
	case "nix":
		return s.Quiet("nix-env", "-q", name) == nil || strings.Contains(s.quietOutput("nix", "profile", "list"), "."+name)
	}
	return false
}

// quietOutput returns a command's stdout like $(cmd 2>/dev/null), and ignores its error.
func (s *Setup) quietOutput(name string, args ...string) string {
	c := s.Cmd(name, args...)
	c.Stdout, c.Stderr = nil, nil
	out, _ := c.Output()
	return strings.TrimRight(string(out), "\n")
}
