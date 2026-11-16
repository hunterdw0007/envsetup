package setup

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/hunterdw0007/envsetup/internal/ui"
)

// Actions lists the menu, in order, after "Select profile (current: ...)".
// The names are part of the API (docs/interface.md).
var actions = []string{"Paste config", "Edit config", "Link shell config",
	"Set up zsh + oh-my-zsh", "Configure git", "Set up SSH key", "Install packages", "Run installers",
	"Move dotfiles to XDG dirs", "Preview everything", "Run everything", "Check status", "Uninstall", "Quit"}

// MainMenu shows the menu until the user quits (envsetup::main_menu).
func (s *Setup) MainMenu() {
	if s.ReadState("profile", "") == "" {
		s.UI.Print(ui.Style{ui.Border("normal"), ui.Padding(0, 1)},
			"Welcome to envsetup. Nothing changes until you select an action.",
			"1. Select profile tells envsetup what kind of machine this is. You can change it at any time.",
			"2. Preview everything shows the changes. It does not make them.",
			"3. Run everything, or run the steps one at a time.",
			"Put your own changes in Paste config or Edit config. For more, run ./setup.sh --help")
	}
	for {
		profile := s.ReadState("profile", "")
		s.LoadConfig(profile, s.ReadState("mode", "full"))
		label := profile
		if label == "" {
			label = "none"
		}
		if profile == "work" {
			label += " (" + s.Cfg.Mode + ")"
		}
		choice, ok := s.UI.Choose("", append([]string{"Select profile (current: " + label + ")"}, actions...)...)
		if !ok { // Esc or Ctrl-C
			return
		}
		switch choice {
		case "Install packages", "Run installers", "Preview everything", "Run everything":
			if profile == "" {
				s.Color(1, "Select a profile first.")
				continue
			}
		}
		switch {
		case strings.HasPrefix(choice, "Select profile"):
			s.RunStep(s.PickProfile)
		case choice == "Paste config":
			if s.DryRun {
				s.Color(6, "Dry run: Paste config checks only the syntax of the text. It saves the text nowhere.")
			}
			s.RunStep(s.PasteConfig)
		case choice == "Edit config":
			if s.DryRun {
				s.Color(6, "Dry run: you are editing a copy of your config. Your changes last until you quit.")
			}
			s.RunStep(s.EditConfig)
		case choice == "Link shell config":
			s.RunStep(s.LinkShellConfig)
		case choice == "Set up zsh + oh-my-zsh":
			s.RunStep(s.SetUpZsh)
		case choice == "Configure git":
			s.RunStep(s.ConfigureGit)
		case choice == "Set up SSH key":
			s.RunStep(s.SetUpSSHKey)
		case choice == "Install packages":
			s.RunStep(s.InstallPackages)
		case choice == "Run installers":
			s.RunStep(s.RunInstallers)
		case choice == "Move dotfiles to XDG dirs":
			s.RunStep(s.XDGTidy)
		case choice == "Preview everything":
			s.UI.Print(ui.Style{ui.Bold}, "What Run everything would do for "+label+". Nothing changes:")
			dry := s.DryRun
			s.DryRun = true
			s.RunEverything()
			s.DryRun = dry
		case choice == "Run everything":
			if s.DryRun {
				s.UI.Print(ui.Style{ui.Bold}, "Dry run: what Run everything would do for "+label+":")
			}
			s.RunEverything()
		case choice == "Check status":
			s.RunStep(func() error { _, err := s.Status(); return err })
		case choice == "Uninstall":
			// After a real uninstall, the menu has nothing left to work on.
			if s.Uninstall() == nil && !s.DryRun {
				return
			}
		default:
			return
		}
	}
}

// RunEverything runs each step on its own (envsetup::run_everything).
// So a failed step does not stop the other steps.
// The steps and their order are part of the API.
func (s *Setup) RunEverything() {
	for _, step := range []func() error{s.LinkShellConfig, s.ConfigureGit, s.InstallPackages, s.RunInstallers, s.SetUpSSHKey} {
		s.RunStep(step)
	}
	if s.Cfg.XDGNinja == "1" {
		s.RunStep(s.XDGTidy)
	}
}

// PickProfile asks for the profile, and for work also the mode (envsetup::pick_profile).
// It saves nothing until both choices are made, so a cancel changes nothing.
func (s *Setup) PickProfile() error {
	s.Color(4, "What kind of machine is this?")
	profile, ok := s.UI.Choose("", s.profileLabel("work"), s.profileLabel("home"))
	if !ok {
		return nil
	}
	mode := ""
	if first(profile) == "work" {
		s.Color(4, "Do you have sudo on this machine?")
		if mode, ok = s.UI.Choose("", s.modeLabels()...); !ok {
			return nil
		}
	}
	if err := s.SaveState("mode", first(mode)); err != nil {
		return err
	}
	return s.SaveState("profile", first(profile))
}

// first keeps the value of a picker line "<value>  <description>", like ${choice%% *}.
func first(line string) string {
	v, _, _ := strings.Cut(line, " ")
	return v
}

// profileLabel describes a profile from its resolved config (envsetup::profile_label).
func (s *Setup) profileLabel(profile string) string {
	cfg, err := s.Load(profile, "full", s.UserConfig, true)
	if err != nil {
		return profile + "  "
	}
	if cfg.InstallersErr != "" {
		fmt.Fprintln(os.Stderr, cfg.InstallersErr)
	}
	summary := "bash"
	if cfg.Shell == "zsh" {
		summary = "zsh + oh-my-zsh"
	}
	summary += fmt.Sprintf(" · %d packages · ", len(cfg.ResolvedPackages))
	names := installerNames(cfg.ResolvedInstallers)
	switch len(names) {
	case 0:
		summary += "no installers"
	case 1:
		summary += "1 installer (" + names[0] + ")"
	default:
		summary += fmt.Sprintf("%d installers (%s)", len(names), strings.Join(names, ", "))
	}
	return profile + "  " + summary
}

// modeLabels describes the modes of work (envsetup::mode_labels).
func (s *Setup) modeLabels() []string {
	pkgs, scripts := 0, 0
	if cfg, err := s.Load("work", "full", s.UserConfig, true); err == nil {
		if cfg.InstallersErr != "" {
			fmt.Fprintln(os.Stderr, cfg.InstallersErr)
		}
		pkgs, scripts = len(cfg.ResolvedPackages), len(cfg.ResolvedInstallers)
	}
	return []string{
		fmt.Sprintf("full  uses sudo: installs %d packages and runs %d installers", pkgs, scripts),
		"lite  no sudo: only the prompt, aliases, git config and SSH key; installs nothing",
	}
}

// installerNames turns script paths into installer names: /x/kubectl.sh -> kubectl.
func installerNames(scripts []string) []string {
	names := make([]string, len(scripts))
	for i, p := range scripts {
		names[i] = strings.TrimSuffix(filepath.Base(p), ".sh")
	}
	return names
}
