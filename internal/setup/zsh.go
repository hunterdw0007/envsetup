package setup

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/hunterdw0007/envsetup/internal/ui"
)

// SetUpZsh sets up zsh + oh-my-zsh and links ~/.zshrc (envsetup::set_up_zsh).
func (s *Setup) SetUpZsh() error {
	if err := s.installZsh(); err != nil {
		return err
	}
	if err := s.copyShell(); err != nil {
		return err
	}
	return s.linkRC(s.Home + "/.zshrc")
}

// installZsh installs zsh, offers it as the login shell and installs oh-my-zsh (envsetup::install_zsh).
func (s *Setup) installZsh() error {
	var missing []string
	// curl downloads the oh-my-zsh installer, and a new desktop may not have curl yet.
	// The base systems of Fedora and Alpine do not include chsh.
	for _, name := range []string{"zsh", "curl", "chsh"} {
		if !HasCmd(name) {
			missing = append(missing, name)
		}
	}
	list := strings.Join(missing, " ")
	if len(missing) > 0 && s.Lite() {
		s.Fail("work (lite) does not assume sudo, so it cannot install " + list + ". Install it yourself, then run this again.")
		return ErrFailed
	}
	shell := os.Getenv("SHELL")
	if s.DryRun {
		if len(missing) > 0 {
			s.Would("install " + list + " (as root)")
		}
		if !strings.HasSuffix(shell, "/zsh") {
			s.Would("ask to make zsh your login shell (chsh)")
		}
		if !isDir(s.Home + "/.oh-my-zsh") {
			s.Would("install oh-my-zsh with its installer from github.com")
		}
		return nil
	}
	if len(missing) > 0 {
		manager := s.PkgManager()
		if manager == "" {
			s.Fail("envsetup found no supported package manager to install " + list + ".")
			return ErrFailed
		}
		s.UI.Print(ui.Heading, "Installing "+list+"...")
		if err := s.PkgInstall(manager, missing...); err != nil {
			return err
		}
	}

	if !strings.HasSuffix(shell, "/zsh") {
		if yes, _ := s.UI.Confirm("Set zsh as your default login shell?", false); yes {
			// envsetup records the change.
			// Uninstall then offers to change back only a login shell that envsetup changed.
			zsh, _ := exec.LookPath("zsh")
			if s.Run("chsh", "-s", zsh) == nil {
				if err := makeMarker(s.ChshMarker); err != nil {
					return err
				}
			}
		}
	}

	if isDir(s.Home + "/.oh-my-zsh") {
		return nil
	}
	s.UI.Print(ui.Heading, "Installing oh-my-zsh...")
	// Do not run `sh -c "$(curl ...)"`.
	// When the download fails, that command runs an empty script and still succeeds.
	// It leaves a ~/.zshrc, and the next install keeps that file.
	// The installer comes from the commit pinned in installers/versions.txt.
	// The installer clones the newest oh-my-zsh, and oh-my-zsh then updates itself.
	commit, err := s.libOutput("envsetup::pin", "ohmyzsh")
	var installer string
	if err == nil {
		installer, err = s.Output("curl", "-fsSL", "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/"+commit+"/tools/install.sh")
	}
	if err != nil {
		s.Fail("Couldn't download the oh-my-zsh installer.")
		return ErrFailed
	}
	// CHSH=no, because the question about the login shell came above.
	// Without it, the installer would ask again.
	c := s.Cmd("sh", "-c", installer)
	c.Env = append(c.Env, "RUNZSH=no", "CHSH=no", "KEEP_ZSHRC=yes")
	return c.Run()
}

// makeMarker creates an empty marker file and its folder, like `mkdir -p "${f%/*}"; : >"$f"`.
func makeMarker(file string) error {
	if err := os.MkdirAll(filepath.Dir(file), 0o777); err != nil {
		return err
	}
	return os.WriteFile(file, nil, 0o666)
}
