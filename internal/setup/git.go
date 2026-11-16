package setup

import (
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// gitKeySet reports whether entries (key=value) set key.
// git keys are case-insensitive, so it compares them in lower case, like ${key,,}.
func gitKeySet(entries []string, key string) bool {
	for _, kv := range entries {
		k, _, _ := strings.Cut(kv, "=")
		if strings.ToLower(k) == strings.ToLower(key) {
			return true
		}
	}
	return false
}

// gitGlobal prints a key of ~/.gitconfig with its includes, or "" (git config --global --includes <key>).
func (s *Setup) gitGlobal(key string, quiet bool) string {
	c := s.Cmd("git", "config", "--global", "--includes", key)
	c.Stdout = nil
	if quiet {
		c.Stderr = nil
	}
	out, _ := c.Output()
	return strings.TrimRight(string(out), "\n")
}

// gitUnset is for the dry run (envsetup::git_unset).
// It is true if key would still have no value after a real run.
// That means neither ENVSETUP_GIT_CONFIG nor ~/.gitconfig with its includes sets key.
func (s *Setup) gitUnset(key string) bool {
	return !gitKeySet(s.Cfg.GitConfig, key) && s.gitGlobal(key, true) == ""
}

// ConfigureGit writes ENVSETUP_GIT_CONFIG to the generated file (envsetup::configure_git).
// ~/.gitconfig includes that file.
// Then it asks for any missing name or email.
// It never needs sudo, so work lite gets it too.
func (s *Setup) ConfigureGit() error {
	generated := s.GitFile
	entries := s.Cfg.GitConfig
	if s.DryRun {
		n := strconv.Itoa(len(entries))
		if s.GitIncluded() {
			s.Would("rewrite " + generated + " (" + n + " git settings)")
		} else {
			s.Would("write " + n + " git settings to " + generated + " and include it from ~/.gitconfig")
		}
		for _, key := range []string{"name", "email"} {
			if s.gitUnset("user." + key) {
				s.Would("ask for your git user." + key)
			}
		}
		return nil
	}

	// The step writes the file again from the start.
	// So entries that the user removes from config.sh also go away.
	// It writes to a temporary file first.
	// So a bad entry leaves the last good file in place.
	// --add keeps git's rules: the last value wins, and keys with more than one value collect them all.
	if err := os.MkdirAll(filepath.Dir(generated), 0o777); err != nil {
		return err
	}
	tmp := generated + ".tmp"
	if err := os.WriteFile(tmp, []byte("# envsetup generates this file from git/gitconfig and config.sh. It overwrites any edits.\n"), 0o666); err != nil {
		return err
	}
	for _, kv := range entries {
		key, value, ok := strings.Cut(kv, "=")
		if !ok {
			value = kv // ${kv#*=} keeps the whole entry when it has no "="
		}
		if err := s.Run("git", "config", "--file", tmp, "--add", key, value); err != nil {
			return err
		}
	}
	if err := os.Rename(tmp, generated); err != nil {
		return err
	}
	if s.GitIncluded() {
		s.Color(2, "Updated "+generated)
	} else {
		if err := s.Run("git", "config", "--global", "--add", "include.path", generated); err != nil {
			return err
		}
		s.Color(2, "Included "+generated+" in $HOME/.gitconfig")
	}

	// --includes is needed, because the name and email may come from config.sh through the generated file.
	// An empty answer skips the key.
	// Esc or Ctrl-C also skips it.
	// So ~/.gitconfig never gets an empty user.name or user.email.
	hint := map[string]string{"name": "Your name", "email": "you@example.com"}
	for _, key := range []string{"name", "email"} {
		if s.gitGlobal("user."+key, true) != "" {
			continue
		}
		value, ok := s.UI.Input(hint[key], "")
		switch {
		case !ok || strings.TrimSpace(value) == "":
			s.Color(3, "Skipped user."+key+". git needs it before your first commit: git config --global user."+key+" ...")
		case key == "email" && !strings.Contains(value, "@"):
			s.Color(3, `Skipped user.email: "`+value+`" is not an email address`)
		default:
			if err := s.Run("git", "config", "--global", "user."+key, value); err != nil {
				return err
			}
		}
	}
	return nil
}
