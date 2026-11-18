package setup

import (
	"os"
	"strings"
)

// This file holds helpers that more than one action uses.

// RemoveRCBlock removes each complete envsetup block from a file (envsetup::remove_rc_block).
// A block runs from the begin marker to the end marker.
// replacement takes each block's place.
// It writes through symlinks.
// It keeps a begin marker without an end marker.
// Otherwise it would remove everything after that marker.
func RemoveRCBlock(file, replacement string) error {
	data, err := os.ReadFile(file)
	if err != nil {
		return err
	}
	var out, held strings.Builder
	inside := false
	for _, line := range splitLines(string(data)) {
		switch {
		case line == RCBegin: // like awk, a second begin marker drops the lines held so far
			held.Reset()
			held.WriteString(line + "\n")
			inside = true
		case inside:
			held.WriteString(line + "\n")
			if line == RCEnd {
				inside = false
				held.Reset()
				out.WriteString(replacement)
			}
		default:
			out.WriteString(line + "\n")
		}
	}
	if inside {
		out.WriteString(held.String())
	}
	// Like `cat tmp >file`, this keeps the file's mode and writes through a link.
	f, err := os.OpenFile(file, os.O_WRONLY|os.O_TRUNC, 0)
	if err != nil {
		return err
	}
	if _, err := f.WriteString(out.String()); err != nil {
		f.Close()
		return err
	}
	return f.Close()
}

// splitLines splits text into lines like awk: a last line without a newline still counts.
func splitLines(text string) []string {
	if text == "" {
		return nil
	}
	return strings.Split(strings.TrimSuffix(text, "\n"), "\n")
}

// GitIncluded reports whether ~/.gitconfig includes the generated file (envsetup::git_included).
func (s *Setup) GitIncluded() bool {
	out, _ := output(s.Cmd("git", "config", "--global", "--get-all", "include.path"), true)
	for _, line := range splitLines(out) {
		if line == s.GitFile {
			return true
		}
	}
	return false
}

// PkgManager prints the package manager, such as apt, or "" (envsetup::pkg_manager).
// Installers use the same function, so it stays in lib/common.sh.
func (s *Setup) PkgManager() string {
	out, _ := s.libOutput("envsetup::pkg_manager")
	return out
}

// PkgName prints the name that the manager uses for a package, or "" when it needs none (envsetup::pkg_name).
func (s *Setup) PkgName(manager, pkg string) string {
	out, _ := s.libOutput("envsetup::pkg_name", manager, pkg)
	return out
}

// PkgInstall installs packages by their names in packages/*.txt (envsetup::pkg_install).
func (s *Setup) PkgInstall(manager string, pkgs ...string) error {
	return s.Lib("envsetup::pkg_install", append([]string{manager}, pkgs...)...).Run()
}

// Pin prints the pinned version of a tool from installers/versions.txt (envsetup::pin).
func (s *Setup) Pin(name string) (string, error) {
	return output(s.Lib("envsetup::pin", name), true)
}

// InstalledVersion prints the version of a tool that envsetup installed, or "" (envsetup::installed_version).
func (s *Setup) InstalledVersion(name string) string {
	out, _ := s.libOutput("envsetup::installed_version", name)
	return out
}

// libOutput runs a function of lib/common.sh and returns its stdout, like $(fn).
// Its stderr goes to the terminal.
func (s *Setup) libOutput(fn string, args ...string) (string, error) {
	return output(s.Lib(fn, args...), false)
}
