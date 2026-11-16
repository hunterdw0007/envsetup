package setup

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/hunterdw0007/envsetup/internal/ui"
)

// RunInstallers runs the installer scripts in ENVSETUP_INSTALLER_DIRS (envsetup::run_installers).
// Installers handle anything that a package manager cannot install.
// Each installer is a separate bash script that is safe to run more than once.
func (s *Setup) RunInstallers() error {
	if s.Lite() {
		s.Color(3, "work (lite) does not assume sudo, so it runs no installers.")
		return nil
	}
	if s.Cfg.InstallersErr != "" {
		fmt.Fprintln(os.Stderr, s.Cfg.InstallersErr)
	}
	scripts := s.Cfg.ResolvedInstallers
	names := installerNames(scripts)
	if len(scripts) == 0 {
		s.Color(3, "No installers for "+s.Cfg.Profile+".")
		return nil
	}
	// An update replaces a tool that envsetup installed at another version than the pin.
	// Your own installers have no pin, so they have no updates.
	var updates []string
	for _, name := range names {
		had := s.InstalledVersion(name)
		pin, err := s.Pin(name)
		if err != nil {
			continue
		}
		if had != "" && had != pin {
			updates = append(updates, name+" "+had+" → "+pin)
		}
	}
	if s.DryRun {
		s.Would(fmt.Sprintf("run %d installer scripts, and each one skips a tool that is already installed: %s", len(scripts), strings.Join(names, " ")))
		for _, u := range updates {
			s.Would("update " + u)
		}
		return nil
	}
	if len(updates) > 0 {
		lines := []string{"Updates:"}
		for _, u := range updates {
			lines = append(lines, "  "+u)
		}
		s.Color(6, lines...)
	}
	var failed []string
	for _, script := range scripts {
		s.UI.Print(ui.Style{ui.Bold, ui.Fg(4)}, "Running "+filepath.Base(script)+"...")
		if s.Run("bash", script) != nil {
			failed = append(failed, filepath.Base(script))
		}
	}
	if len(failed) > 0 {
		s.Color(1, "Installers failed: "+strings.Join(failed, " "))
		return ErrFailed
	}
	return nil
}
