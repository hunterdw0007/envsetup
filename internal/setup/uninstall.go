package setup

// This file removes what setup added.
// That is the startup file block, the copy of shell/, the git include and its generated file, and the saved choices.
// Uninstall cannot safely remove packages or the git name and email.
// So it keeps them, and it says so.

import (
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"syscall"

	"github.com/hunterdw0007/envsetup/internal/ui"
)

// gitRESpecial matches the characters that the bash version escaped with sed 's/[][\.*^$+?(){}|]/\\&/g'.
var gitRESpecial = regexp.MustCompile(`[\]\[\\.*^$+?(){}|]`)

// escapeGitRE escapes a path, so --unset-all's regular expression matches only that path.
func escapeGitRE(p string) string { return gitRESpecial.ReplaceAllString(p, `\$0`) }

// fileHasLine is grep -qxF: some line of the file equals line.
func fileHasLine(file, line string) bool {
	data, err := os.ReadFile(file)
	if err != nil {
		return false
	}
	for _, l := range splitLines(string(data)) {
		if l == line {
			return true
		}
	}
	return false
}

// Uninstall removes what envsetup added (envsetup::uninstall).
// Uninstall returns ErrCancelled after a no, and ErrFailed when a step failed.
// Like the bash version, each step reports its own failure, and the rest still runs.
// Each "Keep …?" question keeps the item on a cancel (Esc or Ctrl-C), as on its default answer.
func (s *Setup) Uninstall() error {
	state, gitconfig, key := s.State, s.GitFile, s.Home+"/.ssh/id_ed25519"
	failed := false
	var kept []string
	s.UI.Print(ui.Heading, "Uninstall removes what envsetup added.",
		"That is its block in your shell startup files, the copy of its shell config,",
		"its git include and its saved choices.",
		"Uninstall also moves back any dotfiles that envsetup moved.",
		"The packages and tools that envsetup installed stay.")
	if yes, _ := s.UI.Confirm("Remove envsetup from this machine?", false); !yes {
		s.Say("Uninstall removed nothing.")
		return ErrCancelled
	}

	chshByUs := isFile(s.ChshMarker) // read this before the state folder is deleted
	keyByUs := isFile(s.SSHMarker)
	for _, rc := range []string{s.Home + "/.bashrc", s.Home + "/.zshrc"} {
		if !isFile(rc) || !fileHasLine(rc, RCBegin) {
			continue
		}
		if s.DryRun {
			s.Would("remove the envsetup block from " + rc)
		} else if RemoveRCBlock(rc, "") == nil {
			s.Success("Removed the envsetup block from " + rc)
		} else {
			s.Fail("Couldn't edit " + rc)
			failed = true
		}
	}

	if s.GitIncluded() {
		if s.DryRun {
			s.Would("remove the include of " + gitconfig + " from ~/.gitconfig")
		} else if s.Run("git", "config", "--global", "--unset-all", "include.path", "^"+escapeGitRE(gitconfig)+"$") == nil {
			s.Success("Removed envsetup's include from ~/.gitconfig")
		} else {
			s.Fail("Couldn't edit ~/.gitconfig")
			failed = true
		}
	}

	// Uninstall removes the signing settings only for a key that envsetup created.
	// The settings must also still name that key.
	if keyByUs {
		if signing, _ := s.Output("git", "config", "--global", "user.signingkey"); signing == key+".pub" {
			if s.DryRun {
				s.Would("remove the settings that sign your commits with " + key + " from ~/.gitconfig")
			} else {
				signFailed := false
				for _, f := range []string{"gpg.format", "user.signingkey", "commit.gpgsign"} {
					// Exit code 5 means that the setting is already gone.
					if err := s.Run("git", "config", "--global", "--unset-all", f); err != nil && exitCode(err) != 5 {
						signFailed = true
					}
				}
				if signFailed {
					s.Fail("Couldn't remove the settings that sign your commits from ~/.gitconfig")
					failed = true
				} else {
					s.Success("Removed the settings that sign your commits with " + key)
				}
			}
		}
	}

	if s.xdgRestore() != nil {
		failed = true
	}

	// The last two files are the prompt's saved Kubernetes context (shell/shared/ps1.sh).
	// And the log of fetchAll --quiet (shell/shared/functions.sh).
	for _, f := range []string{gitconfig, gitconfig + ".tmp", state + "/profile", state + "/mode", s.Installed, s.ChshMarker, s.SSHMarker, s.Data,
		s.CacheDir() + "/kube-context", s.CacheDir() + "/fetchAll.log"} {
		if !statOK(f) {
			continue
		}
		if s.DryRun {
			s.Would("delete " + f)
		} else {
			_ = os.RemoveAll(f)
		}
	}
	// The repo belongs to the user, so the default answer keeps it.
	cfg := state + "/config.sh"
	if isDir(s.Clone) {
		if yes, cancelled := s.UI.Confirm("Keep "+s.Clone+"? It is the clone of your own config repo.", false); yes || cancelled {
			kept = append(kept, "your config repo: "+s.Clone)
		} else if s.DryRun {
			s.Would("delete " + s.Clone)
		} else if target, _ := os.Readlink(cfg); isLink(cfg) && strings.HasPrefix(target, s.Clone+"/") &&
			s.Run("cp", "--remove-destination", target, cfg) != nil {
			// A config.sh that links into the clone becomes a copy, so the next question can keep it.
			// A failed copy must stop the delete.
			s.Fail("Couldn't copy " + cfg + " out of " + s.Clone + ", so uninstall keeps the clone")
			failed = true
		} else {
			_ = os.RemoveAll(s.Clone)
		}
	}
	// isLink also finds a link to a config.sh that is gone.
	if isFile(cfg) || isLink(cfg) {
		if yes, cancelled := s.UI.Confirm("Keep your own config ("+cfg+")?", false); yes || cancelled {
			kept = append(kept, "your config: "+cfg)
		} else if s.DryRun {
			s.Would("delete " + cfg)
		} else {
			_ = os.Remove(cfg)
		}
	}
	// The files in shell.d are your own.
	// So uninstall removes the folder only when it is empty, and asks otherwise.
	if isDir(s.ShellD) {
		if entries, _ := os.ReadDir(s.ShellD); len(entries) > 0 {
			if yes, cancelled := s.UI.Confirm("Keep "+s.ShellD+"? It holds your own shell files.", false); yes || cancelled {
				kept = append(kept, "your shell files: "+s.ShellD)
			} else if s.DryRun {
				s.Would("delete " + s.ShellD)
			} else {
				_ = os.RemoveAll(s.ShellD)
			}
		} else if s.DryRun {
			s.Would("delete the empty " + s.ShellD)
		} else {
			rmdir(s.ShellD, true)
		}
	}
	// Uninstall asks only about a key that envsetup created.
	// The key stays unless you say no.
	if keyByUs && statOK(key) {
		if yes, cancelled := s.UI.Confirm("Keep ~/.ssh/id_ed25519? It is this machine's SSH key.", false); yes || cancelled {
			kept = append(kept, "your SSH key: "+key)
		} else if s.DryRun {
			s.Would("delete " + key + " and " + key + ".pub")
		} else {
			_ = os.Remove(key)
			_ = os.Remove(key + ".pub")
			rmdir(s.Home+"/.ssh", false) // rmdir works only if ~/.ssh is now empty
		}
	}
	if !s.DryRun {
		for _, d := range []string{state, filepath.Dir(s.Installed), s.CacheDir()} {
			rmdir(d, false)
		}
	}

	// Uninstall asks only if envsetup changed your login shell to zsh.
	// It leaves a zsh that you chose yourself alone.
	if strings.HasSuffix(os.Getenv("SHELL"), "/zsh") && chshByUs {
		if yes, cancelled := s.UI.Confirm("Keep zsh as your login shell?", false); yes || cancelled {
			kept = append(kept, "zsh as your login shell")
		} else if s.DryRun {
			s.Would("change your login shell back to bash (chsh)")
		} else {
			bash, _ := exec.LookPath("bash")
			if s.Run("chsh", "-s", bash) != nil {
				s.Fail("Couldn't change your login shell")
				failed = true
			}
		}
	}

	// The old config.sh that SyncConfigRepo moved aside is the user's file.
	if statOK(state + "/config.sh.bak") {
		kept = append(kept, "your old config: "+state+"/config.sh.bak")
	}
	if isDir(s.Home + "/.oh-my-zsh") {
		kept = append(kept, "oh-my-zsh: remove it with uninstall_oh_my_zsh")
	}
	lines := []string{"Left in place:",
		"- the packages and tools that envsetup installed. They may be older than envsetup, so remove them yourself.",
		"- your git user.name and user.email"}
	for _, k := range kept {
		lines = append(lines, "- "+k)
	}
	s.Say(lines...)
	if failed {
		return ErrFailed
	}
	return nil
}

// rmdir removes an empty folder, like rmdir.
// It shows rmdir's error only when loud is true; the bash version sent the others to /dev/null.
func rmdir(dir string, loud bool) {
	if err := syscall.Rmdir(dir); err != nil && loud {
		os.Stderr.WriteString("rmdir: failed to remove '" + dir + "': " + err.Error() + "\n")
	}
}
