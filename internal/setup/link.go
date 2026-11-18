package setup

import (
	"os"
	"path/filepath"
	"strings"
)

// LinkShellConfig links the shell config (envsetup::link_shell_config).
// It always links ~/.bashrc, so every bash gets the config.
// It also links the login shell's startup file, so new terminals get the config.
// It sets up zsh + oh-my-zsh only when ENVSETUP_SHELL=zsh opts in.
// It also creates shell.d for the user's own shell files.
func (s *Setup) LinkShellConfig() error {
	s.asked = "" // bash ran each step in a subshell, so each step could ask again
	if err := s.copyShell(); err != nil {
		return err
	}
	if !isDir(s.ShellD) {
		if s.DryRun {
			s.Would("create " + s.ShellD + " for your own shell files")
		} else {
			if err := os.MkdirAll(s.ShellD, 0o777); err != nil {
				return err
			}
			s.Success("Created " + s.ShellD + ". New shells load your own shell files from it.")
		}
	}
	if err := s.linkRC(s.Home + "/.bashrc"); err != nil {
		return err
	}
	if filepath.Base(os.Getenv("SHELL")) == "zsh" {
		if err := s.linkRC(s.Home + "/.zshrc"); err != nil {
			return err
		}
	}
	if s.Cfg.Shell == "zsh" {
		if err := s.installZsh(); err != nil {
			return err
		}
		return s.linkRC(s.Home + "/.zshrc")
	}
	return nil
}

// copyShell copies shell/ to ENVSETUP_DATA and records the release (envsetup::copy_shell).
// New shells load that copy, not the clone, because install.sh deletes its download.
// Each run replaces the copy.
func (s *Setup) copyShell() error {
	if s.DryRun {
		s.Would("copy shell/ (" + s.Version + ") to " + s.Data + ", which new shells load")
		return nil
	}
	if err := os.MkdirAll(s.Data, 0o777); err != nil {
		return err
	}
	if err := os.RemoveAll(s.Data + "/shell"); err != nil {
		return err
	}
	// cp -R gives the same modes, links and errors as the bash version.
	if err := s.Run("cp", "-R", s.Root+"/shell", s.Data+"/"); err != nil {
		return err
	}
	if err := os.WriteFile(s.Data+"/version", []byte(s.Version+"\n"), 0o666); err != nil {
		return err
	}
	s.Success("Copied shell config (" + s.Version + ") to " + s.Data)
	return nil
}

// rcBlock returns the block that loads the copy of shell/init.sh, and its export line for ENVSETUP_ROOT.
// The block sets ENVSETUP_STATE, so every shell uses the folder that setup used (see shell/state.sh).
// Quote keeps a space, ", $ or ` in a path from breaking the startup file.
// bash and zsh both read the output of printf %q.
func rcBlock(data, state, home string) (block, root string) {
	root = "export ENVSETUP_ROOT=" + Quote(data)
	lines := []string{RCBegin, root,
		"export ENVSETUP_STATE=" + Quote(state) + " ENVSETUP_STATE_HOME=" + Quote(home),
		`[ -f "$ENVSETUP_ROOT/shell/init.sh" ] && source "$ENVSETUP_ROOT/shell/init.sh"`,
		RCEnd}
	return strings.Join(lines, "\n") + "\n", root
}

// rootLine returns the first line that starts with "export ENVSETUP_ROOT=", like grep -m 1.
func rootLine(text string) (string, bool) {
	for _, line := range splitLines(text) {
		if strings.HasPrefix(line, "export ENVSETUP_ROOT=") {
			return line, true
		}
	}
	return "", false
}

// hasLine reports whether text has a line equal to line, like grep -qxF.
func hasLine(text, line string) bool {
	for _, l := range splitLines(text) {
		if l == line {
			return true
		}
	}
	return false
}

// linkRC adds the block to a startup file, only once (envsetup::link_rc).
// Older releases loaded shell/ from a checkout (~/envsetup).
// linkRC rewrites such an old block in place.
func (s *Setup) linkRC(file string) error {
	block, root := rcBlock(s.Data, s.State, s.Home)
	data, err := os.ReadFile(file)
	if err == nil && isFile(file) && strings.Contains(string(data), RCBegin) {
		if hasLine(string(data), root) {
			s.Warn("Already linked in " + file)
			return nil
		}
		old := s.oldRoot(string(data))
		if s.DryRun {
			s.Would("rewrite the envsetup block in " + file + " to load shell/ from " + s.Data)
		} else {
			if err := RemoveRCBlock(file, block); err != nil {
				return err
			}
			s.Success("Rewrote the envsetup block in " + file + " to load shell/ from " + s.Data)
		}
		return s.dropCheckout(old)
	}
	if s.DryRun {
		s.Would("add a 5-line block to " + file + " that loads shell/ from " + s.Data)
		return nil
	}
	f, err := os.OpenFile(file, os.O_WRONLY|os.O_APPEND|os.O_CREATE, 0o666)
	if err != nil {
		return err
	}
	if _, err := f.WriteString(block); err != nil {
		f.Close()
		return err
	}
	if err := f.Close(); err != nil {
		return err
	}
	s.Success("Linked shell config into " + file + ". Open a new shell to load it.")
	return nil
}

// oldRoot finds the checkout that an old block loaded, or "".
// Running the block's own export line in bash undoes the quotes of printf %q.
func (s *Setup) oldRoot(text string) string {
	line, ok := rootLine(text)
	if !ok {
		return ""
	}
	c := s.Cmd("bash", "-c", line+`; printf %s "$ENVSETUP_ROOT"`)
	c.Stdout, c.Stderr = nil, nil
	out, err := c.Output()
	if err != nil {
		return ""
	}
	return string(out)
}

// dropCheckout offers to delete the checkout that an old block loaded shell/ from (envsetup::drop_checkout).
// Nothing needs that checkout any more.
// It asks only once in each step.
// The default answer keeps the checkout.
func (s *Setup) dropCheckout(dir string) error {
	if !isFile(dir+"/shell/init.sh") || dir == s.Data || dir == s.asked {
		return nil
	}
	s.asked = dir
	if dir == s.Root {
		s.Say("New shells no longer load " + dir + ". You can delete it after setup ends. Keep it if you work on envsetup there.")
		return nil
	}
	// A cancel (Esc or Ctrl-C) keeps the checkout, like the default answer.
	if keep, cancelled := s.UI.Confirm("Keep "+dir+"? New shells and updates no longer use it.", false); keep || cancelled {
		return nil
	}
	if s.DryRun {
		s.Would("delete " + dir)
		return nil
	}
	if err := os.RemoveAll(dir); err != nil {
		return err
	}
	s.Success("Deleted " + dir)
	return nil
}
