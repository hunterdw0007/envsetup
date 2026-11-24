package setup

// This file tests the actions that change config.sh: EditConfig, PasteConfig, AddConfig,
// MigrateConfig and SyncConfigRepo (issue #191).
// Each action gets the four cases: dry run, first run, second run and uninstall.

import (
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

// cfgSetup returns a home Setup whose git runs for real.
// load_config reads git/gitconfig with git, so SettingsOf and Load need it.
// Every git call in these tests stays in a temporary folder.
func cfgSetup(t *testing.T) (*Setup, *fakeUI, *fakes) {
	t.Helper()
	s, u, f := newTestSetup(t, "home", "full")
	f.passThrough("git")
	f.remove("zsh") // only bash checks a pasted .sh file, unless a test sets zsh
	return s, u, f
}

// cfgWrite writes a file and its folder.
func cfgWrite(t *testing.T, file, text string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(file), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(file, []byte(text), 0o644); err != nil {
		t.Fatal(err)
	}
}

// cfgRead returns a file's text, or "<missing>".
func cfgRead(t *testing.T, file string) string {
	t.Helper()
	data, err := os.ReadFile(file)
	if errors.Is(err, os.ErrNotExist) {
		return "<missing>"
	} else if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

// cfgScript writes an executable shell script and returns its path.
func cfgScript(t *testing.T, body string) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), "script")
	if err := os.WriteFile(p, []byte("#!/bin/sh\n"+body+"\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	return p
}

// cfgLogged reports whether the fake UI logged this exact line.
func cfgLogged(u *fakeUI, line string) bool { return slices.Contains(u.log, line) }

// cfgLoggedPrefix reports whether the fake UI logged a line that starts with prefix.
func cfgLoggedPrefix(u *fakeUI, prefix string) bool {
	return slices.ContainsFunc(u.log, func(l string) bool { return strings.HasPrefix(l, prefix) })
}

// cfgClearCalls forgets the calls so far, such as the git calls that build a test repo.
func cfgClearCalls(t *testing.T, f *fakes) {
	t.Helper()
	if err := os.Remove(filepath.Join(f.dir, "calls")); err != nil && !os.IsNotExist(err) {
		t.Fatal(err)
	}
}

// cfgGit runs git through the pass-through fake, so it must be set.
func cfgGit(t *testing.T, args ...string) {
	t.Helper()
	c := exec.Command("git", args...)
	if out, err := c.CombinedOutput(); err != nil {
		t.Fatalf("git %q: %v\n%s", args, err, out)
	}
}

// cfgUninstall runs Uninstall with yes to "Remove envsetup?" and the given answer to "Keep your own config?".
func cfgUninstall(t *testing.T, s *Setup, u *fakeUI, keep string) {
	t.Helper()
	u.answer("yes", keep)
	if err := s.Uninstall(); err != nil {
		t.Fatalf("Uninstall: %v\n%s", err, strings.Join(u.log, "\n"))
	}
	if !cfgLoggedPrefix(u, "confirm: Keep your own config (") {
		t.Errorf("Uninstall did not ask about config.sh:\n%s", strings.Join(u.log, "\n"))
	}
}

func TestEditConfig(t *testing.T) {
	s, u, _ := cfgSetup(t)
	args := filepath.Join(t.TempDir(), "args")
	// The editor logs its arguments and adds a package, as a user would.
	t.Setenv("EDITOR", cfgScript(t, `echo "$@" >"`+args+`"; echo 'ENVSETUP_PACKAGES+=(smoke-pkg)' >>"$2"`)+" --wait")

	// First run: no config.sh, so the action copies config.example.sh and opens the copy.
	if err := s.EditConfig(); err != nil {
		t.Fatalf("EditConfig: %v\n%s", err, strings.Join(u.log, "\n"))
	}
	example := cfgRead(t, s.Root+"/config.example.sh")
	if got := cfgRead(t, s.UserConfig); got != example+"ENVSETUP_PACKAGES+=(smoke-pkg)\n" {
		t.Errorf("config.sh = %q, want config.example.sh and the editor's line", got)
	}
	if got := cfgRead(t, args); got != "--wait "+s.UserConfig+"\n" {
		t.Errorf("EDITOR got %q, want --wait and the file", got)
	}
	if !cfgLogged(u, "plain: Packages: +smoke-pkg") {
		t.Errorf("EditConfig did not show the change:\n%s", strings.Join(u.log, "\n"))
	}

	// Second run: an editor that changes nothing changes nothing.
	before := cfgRead(t, s.UserConfig)
	t.Setenv("EDITOR", "true")
	u.log = nil
	if err := s.EditConfig(); err != nil {
		t.Fatal(err)
	}
	if cfgRead(t, s.UserConfig) != before || !cfgLogged(u, "plain: No ENVSETUP_* setting changed.") {
		t.Errorf("a second run changed config.sh or said so:\n%s", strings.Join(u.log, "\n"))
	}

	// Uninstall: yes keeps config.sh.
	cfgUninstall(t, s, u, "yes")
	if cfgRead(t, s.UserConfig) != before {
		t.Error("Uninstall with Keep: yes changed config.sh")
	}
}

func TestEditConfigUninstallNoDeletes(t *testing.T) {
	s, u, f := cfgSetup(t)
	t.Setenv("EDITOR", "true")
	if err := s.EditConfig(); err != nil {
		t.Fatal(err)
	}
	f.set("git", fakeCmd{Code: 1}) // no include in ~/.gitconfig
	cfgUninstall(t, s, u, "no")
	if got := cfgRead(t, s.UserConfig); got != "<missing>" {
		t.Errorf("Uninstall with Keep: no left config.sh: %q", got)
	}
}

// main.go points UserConfig at a copy of the state folder in a dry run.
// EditConfig then edits only that copy.
func TestEditConfigDryRunEditsACopy(t *testing.T) {
	s, u, _ := cfgSetup(t)
	cfgWrite(t, s.UserConfig, "ENVSETUP_SHELL=bash\n")
	before := snapshotHome(t)
	s.DryRun = true
	s.StateDir = s.Tmp + "/state"
	if err := os.Mkdir(s.StateDir, 0o777); err != nil {
		t.Fatal(err)
	}
	copyTree(s.State, s.StateDir)
	s.UserConfig = s.StateDir + "/config.sh"
	t.Setenv("EDITOR", cfgScript(t, `echo 'ENVSETUP_SHELL=zsh' >>"$1"`))
	if err := s.EditConfig(); err != nil {
		t.Fatal(err)
	}
	if d := diffSnapshots(before, snapshotHome(t)); len(d) > 0 {
		t.Errorf("the dry run changed HOME: %q", d)
	}
	if !strings.HasSuffix(cfgRead(t, s.UserConfig), "ENVSETUP_SHELL=zsh\n") || !cfgLogged(u, "plain: Shell: +zsh -bash") {
		t.Errorf("the copy did not get the edit:\n%s", strings.Join(u.log, "\n"))
	}
}

func TestEditConfigErrors(t *testing.T) {
	s, u, _ := cfgSetup(t)
	cfgWrite(t, s.UserConfig, "x=1\n")

	t.Setenv("EDITOR", "false")
	if err := s.EditConfig(); exitCode(err) != 1 {
		t.Errorf("a failed editor: %v, want its exit code 1", err)
	}

	t.Setenv("EDITOR", cfgScript(t, `echo 'if true' >>"$1"`))
	if err := s.EditConfig(); !errors.Is(err, ErrFailed) {
		t.Errorf("a syntax error: %v, want ErrFailed", err)
	}
	if !cfgLoggedPrefix(u, "fail: "+s.UserConfig+" has an error.") || !cfgLoggedPrefix(u, "fail: line ") {
		t.Errorf("no error message with the line:\n%s", strings.Join(u.log, "\n"))
	}
}

func TestEditConfigWithoutEditor(t *testing.T) {
	s, _, f := cfgSetup(t)
	cfgWrite(t, s.UserConfig, "x=1\n")
	t.Setenv("EDITOR", "")
	f.set("nano", fakeCmd{})
	f.set("vi", fakeCmd{})
	if err := s.EditConfig(); err != nil {
		t.Fatal(err)
	}
	f.remove("nano")
	f.cmds["nano"] = fakeCmd{} // the call above was expected, so the cleanup passes
	if err := s.EditConfig(); err != nil {
		t.Fatal(err)
	}
	want := []string{"nano " + s.UserConfig, "vi " + s.UserConfig}
	var got []string
	for _, c := range f.calls() {
		if !strings.HasPrefix(c, "git ") {
			got = append(got, c)
		}
	}
	if !slices.Equal(got, want) {
		t.Errorf("editor calls = %q, want %q", got, want)
	}
}

// A config.sh that links into a config repo gets a warning, and the edit goes into the repo.
// A link to a file that is gone becomes a new config.sh, so the edit never writes into the clone.
func TestEditConfigLinks(t *testing.T) {
	s, u, _ := cfgSetup(t)
	repoFile := s.Clone + "/config.sh"
	cfgWrite(t, repoFile, "x=1\n")
	if err := os.Symlink(repoFile, s.UserConfig); err != nil {
		t.Fatal(err)
	}
	t.Setenv("EDITOR", cfgScript(t, `echo y=2 >>"$1"`))
	if err := s.EditConfig(); err != nil {
		t.Fatal(err)
	}
	if cfgRead(t, repoFile) != "x=1\ny=2\n" || !isLink(s.UserConfig) {
		t.Errorf("the edit did not go through the link: %q", cfgRead(t, repoFile))
	}
	if !cfgLoggedPrefix(u, "warn: This config.sh is in your config repo.") {
		t.Errorf("no config repo warning:\n%s", strings.Join(u.log, "\n"))
	}

	if err := os.Remove(repoFile); err != nil {
		t.Fatal(err)
	}
	u.log = nil
	if err := s.EditConfig(); err != nil {
		t.Fatal(err)
	}
	if isLink(s.UserConfig) || !strings.HasSuffix(cfgRead(t, s.UserConfig), "y=2\n") || cfgRead(t, repoFile) != "<missing>" {
		t.Error("the link to a file that is gone did not become a new config.sh")
	}
	if !cfgLoggedPrefix(u, "warn: "+s.UserConfig+" linked to a file that is gone.") {
		t.Errorf("no warning about the link:\n%s", strings.Join(u.log, "\n"))
	}
}

func TestEditorArgs(t *testing.T) {
	for _, tc := range []struct {
		editor string
		nano   bool
		want   []string
	}{
		{"code --wait", false, []string{"code", "--wait"}},
		{"  vim  -u NONE ", true, []string{"vim", "-u", "NONE"}},
		{"emacs\nignored", true, []string{"emacs"}},
		{"", true, []string{"nano"}},
		{"", false, []string{"vi"}},
	} {
		if got := editorArgs(tc.editor, tc.nano); !slices.Equal(got, tc.want) {
			t.Errorf("editorArgs(%q, %v) = %q, want %q", tc.editor, tc.nano, got, tc.want)
		}
	}
}

func TestAddConfig(t *testing.T) {
	s, u, _ := cfgSetup(t)
	cfgWrite(t, s.UserConfig, "ENVSETUP_SHELL=bash") // no newline at the end
	add := filepath.Join(t.TempDir(), "add.sh")
	cfgWrite(t, add, "ENVSETUP_PACKAGES+=(smoke-pkg)\r\n")

	// Dry run: checks the syntax, describes the change and writes nothing.
	s.DryRun = true
	before := snapshotHome(t)
	if err := s.AddConfig(add); err != nil {
		t.Fatal(err)
	}
	if d := diffSnapshots(before, snapshotHome(t)); len(d) > 0 {
		t.Errorf("the dry run changed HOME: %q", d)
	}
	if !cfgLogged(u, "note:   would add the text to the end of config.sh") {
		t.Errorf("the dry run did not describe the change:\n%s", strings.Join(u.log, "\n"))
	}

	// First run: adds the text on a new line, without the \r.
	s.DryRun = false
	u.log = nil
	if err := s.AddConfig(add); err != nil {
		t.Fatal(err)
	}
	want := "ENVSETUP_SHELL=bash\nENVSETUP_PACKAGES+=(smoke-pkg)\n"
	if got := cfgRead(t, s.UserConfig); got != want {
		t.Errorf("config.sh = %q, want %q", got, want)
	}
	if !cfgLogged(u, "success: Added the text to the end of "+s.UserConfig) || !cfgLogged(u, "plain: Packages: +smoke-pkg") {
		t.Errorf("no success or change:\n%s", strings.Join(u.log, "\n"))
	}

	// Second run: empty text saves nothing more.
	cfgWrite(t, add, " \n\t\n")
	u.log = nil
	if err := s.AddConfig(add); err != nil {
		t.Fatal(err)
	}
	if cfgRead(t, s.UserConfig) != want || !cfgLogged(u, "warn: The text is empty, so envsetup saved nothing.") {
		t.Errorf("empty text changed config.sh:\n%s", strings.Join(u.log, "\n"))
	}

	// Uninstall: no deletes config.sh.
	cfgUninstall(t, s, u, "no")
	if cfgRead(t, s.UserConfig) != "<missing>" {
		t.Error("Uninstall with Keep: no left config.sh")
	}

	if err := s.AddConfig(filepath.Join(t.TempDir(), "missing")); err == nil {
		t.Error("AddConfig of a missing file returned no error")
	}
}

// Each bad text saves nothing and shows why.
func TestAddConfigSavesNothing(t *testing.T) {
	for _, tc := range []struct{ name, config, text, msg string }{
		{"syntax error in the text", "x=1\n", "if true\n", "fail: The text has an error, so envsetup saved nothing:"},
		{"syntax error in config.sh", "if true\n", "y=2\n", "fail: config.sh already has an error, so envsetup saved nothing."},
		// Each part is fine alone, but the line continuation joins them.
		{"syntax error together", "echo \\\n", "(echo)\n", "fail: config.sh with the text at its end has an error, so envsetup saved nothing:"},
		{"exit in the text", "x=1\n", "exit 0\n", "fail: config.sh with the text would stop before its end, for example at an exit."},
	} {
		t.Run(tc.name, func(t *testing.T) {
			s, u, _ := cfgSetup(t)
			cfgWrite(t, s.UserConfig, tc.config)
			add := filepath.Join(t.TempDir(), "add.sh")
			cfgWrite(t, add, tc.text)
			if err := s.AddConfig(add); !errors.Is(err, ErrFailed) {
				t.Errorf("AddConfig: %v, want ErrFailed", err)
			}
			if got := cfgRead(t, s.UserConfig); got != tc.config {
				t.Errorf("config.sh = %q, want it unchanged", got)
			}
			if !cfgLoggedPrefix(u, tc.msg) {
				t.Errorf("no %q in:\n%s", tc.msg, strings.Join(u.log, "\n"))
			}
		})
	}
}

// The text goes through a link into the config repo and keeps the file's mode.
func TestAddConfigThroughLink(t *testing.T) {
	s, u, _ := cfgSetup(t)
	repoFile := s.Clone + "/config.sh"
	cfgWrite(t, repoFile, "x=1\n")
	if err := os.Chmod(repoFile, 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(repoFile, s.UserConfig); err != nil {
		t.Fatal(err)
	}
	add := filepath.Join(t.TempDir(), "add.sh")
	cfgWrite(t, add, "y=2\n")
	if err := s.AddConfig(add); err != nil {
		t.Fatal(err)
	}
	fi, err := os.Stat(repoFile)
	if err != nil {
		t.Fatal(err)
	}
	if cfgRead(t, repoFile) != "x=1\ny=2\n" || !isLink(s.UserConfig) || fi.Mode().Perm() != 0o600 {
		t.Errorf("repo file = %q, mode %v; link kept: %v", cfgRead(t, repoFile), fi.Mode().Perm(), isLink(s.UserConfig))
	}
	if !cfgLoggedPrefix(u, "warn: This config.sh is in your config repo.") {
		t.Errorf("no config repo warning:\n%s", strings.Join(u.log, "\n"))
	}
}

func TestWriteThrough(t *testing.T) {
	dir := t.TempDir()
	if err := writeThrough(dir+"/new", "a\n"); err != nil || cfgRead(t, dir+"/new") != "a\n" {
		t.Errorf("writeThrough to a new file: %v", err)
	}
	if err := writeThrough(dir, "a\n"); err == nil {
		t.Error("writeThrough to a folder returned no error")
	}
	// Linux's /dev/full opens, but every write fails, as on a full disk.
	if err := writeThrough("/dev/full", "a\n"); err == nil {
		t.Error("writeThrough to /dev/full returned no error")
	}
}

func TestPasteConfigSettings(t *testing.T) {
	s, u, _ := cfgSetup(t)
	u.answer("ENVSETUP_SHELL=zsh", "settings")
	if err := s.PasteConfig(); err != nil {
		t.Fatal(err)
	}
	if got := cfgRead(t, s.UserConfig); got != "ENVSETUP_SHELL=zsh\n" {
		t.Errorf("config.sh = %q", got)
	}
	// A cancel at either question saves nothing.
	u.answer(cancel, "x=1", cancel)
	for range 2 {
		if err := s.PasteConfig(); err != nil {
			t.Fatal(err)
		}
	}
	if got := cfgRead(t, s.UserConfig); got != "ENVSETUP_SHELL=zsh\n" {
		t.Errorf("a cancel changed config.sh: %q", got)
	}
}

func TestPasteConfigShellFile(t *testing.T) {
	s, u, _ := cfgSetup(t)
	file := s.ShellD + "/mine.sh"

	// Dry run: checks the syntax only, describes the save and writes nothing.
	s.DryRun = true
	before := snapshotHome(t)
	u.answer("alias ll='ls -l'\r\n", "shell", "mine")
	if err := s.PasteConfig(); err != nil {
		t.Fatal(err)
	}
	if d := diffSnapshots(before, snapshotHome(t)); len(d) > 0 {
		t.Errorf("the dry run changed HOME: %q", d)
	}
	if !cfgLogged(u, "note:   would save the text as "+file) || !cfgLogged(u, "warn: A dry run does not run the text. It checks only the syntax.") {
		t.Errorf("the dry run did not describe the save:\n%s", strings.Join(u.log, "\n"))
	}

	// First run: saves the file, with .sh added to the name.
	s.DryRun = false
	u.answer("alias ll='ls -l'\r\n", "shell", "mine")
	if err := s.PasteConfig(); err != nil {
		t.Fatal(err)
	}
	if got := cfgRead(t, file); got != "alias ll='ls -l'\n" {
		t.Errorf("%s = %q", file, got)
	}

	// Second run: the same name asks to replace, and no keeps the old file.
	u.answer("alias ll='ls -la'", "shell", "mine.sh", "no")
	if err := s.PasteConfig(); err != nil {
		t.Fatal(err)
	}
	if got := cfgRead(t, file); got != "alias ll='ls -l'\n" || !cfgLogged(u, "plain: envsetup kept the old mine.sh and saved nothing.") {
		t.Errorf("no to Replace changed the file: %q", got)
	}
	// A dry run only says that it would ask.
	s.DryRun = true
	u.answer("alias ll='ls -la'", "shell", "mine.sh")
	if err := s.PasteConfig(); err != nil {
		t.Fatal(err)
	}
	if !cfgLogged(u, "note:   would ask to replace "+file) {
		t.Errorf("the dry run did not describe the question:\n%s", strings.Join(u.log, "\n"))
	}
	s.DryRun = false
	// Yes replaces a link with a file, and the link's target stays.
	target := filepath.Join(t.TempDir(), "target.sh")
	cfgWrite(t, target, "# target\n")
	if err := os.Remove(file); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(target, file); err != nil {
		t.Fatal(err)
	}
	u.answer("alias ll='ls -la'", "shell", "mine.sh", "yes")
	if err := s.PasteConfig(); err != nil {
		t.Fatal(err)
	}
	if isLink(file) || cfgRead(t, file) != "alias ll='ls -la'\n" || cfgRead(t, target) != "# target\n" {
		t.Errorf("yes to Replace: file %q, target %q", cfgRead(t, file), cfgRead(t, target))
	}

	// Uninstall: yes keeps shell.d.
	u.answer("yes", "yes", "yes") // remove; keep config.sh; keep shell.d
	cfgWrite(t, s.UserConfig, "x=1\n")
	if err := s.Uninstall(); err != nil {
		t.Fatal(err)
	}
	if cfgRead(t, file) != "alias ll='ls -la'\n" || !cfgLoggedPrefix(u, "confirm: Keep "+s.ShellD+"?") {
		t.Errorf("Uninstall did not keep shell.d:\n%s", strings.Join(u.log, "\n"))
	}
}

// Each bad paste saves nothing in shell.d.
func TestPasteConfigShellFileSavesNothing(t *testing.T) {
	for _, tc := range []struct {
		name    string
		answers []string
		err     error
		msg     string
	}{
		{"empty text", []string{" \n", "shell"}, nil, "warn: The text is empty, so envsetup saved nothing."},
		{"cancelled name", []string{"x=1", "shell", cancel}, nil, ""},
		{"empty name", []string{"x=1", "shell", ""}, nil, ""},
		{"bad name", []string{"x=1", "shell", "../x"}, nil, `warn: "../x" is not a file name, so envsetup saved nothing.`},
		{"syntax error", []string{"if true", "shell", "a"}, ErrFailed, "fail: The text has an error in bash, so envsetup saved nothing:"},
		{"exit", []string{"exit 0", "shell", "a"}, ErrFailed, "fail: The text stops before its end in bash, for example at an exit."},
	} {
		t.Run(tc.name, func(t *testing.T) {
			s, u, _ := cfgSetup(t)
			u.answer(tc.answers...)
			if err := s.PasteConfig(); !errors.Is(err, tc.err) {
				t.Errorf("PasteConfig: %v, want %v", err, tc.err)
			}
			if isDir(s.ShellD) {
				t.Error("PasteConfig created shell.d")
			}
			if tc.msg != "" && !cfgLoggedPrefix(u, tc.msg) {
				t.Errorf("no %q in:\n%s", tc.msg, strings.Join(u.log, "\n"))
			}
		})
	}
}

// zsh checks each file that it loads: .sh and .zsh, not .bash.
func TestPasteConfigShellFileZsh(t *testing.T) {
	s, u, f := cfgSetup(t)
	f.set("zsh", fakeCmd{Out: "envsetup-ok\n"})
	u.answer("x=1", "shell", "a.zsh", "x=1", "shell", "b.bash")
	for range 2 {
		if err := s.PasteConfig(); err != nil {
			t.Fatal(err)
		}
	}
	var zsh []string
	for _, c := range f.calls() {
		if name, _, _ := strings.Cut(c, " "); name == "zsh" {
			zsh = append(zsh, strings.Fields(c)[1])
		}
	}
	if !slices.Equal(zsh, []string{"-n", "-fc"}) {
		t.Errorf("zsh calls = %q, want one -n and one -fc, for a.zsh only", zsh)
	}
	if cfgRead(t, s.ShellD+"/a.zsh") != "x=1\n" || cfgRead(t, s.ShellD+"/b.bash") != "x=1\n" {
		t.Error("the files were not saved")
	}

	// Without zsh, a .zsh file cannot be checked, but it is saved.
	f.remove("zsh")
	f.cmds["zsh"] = fakeCmd{} // the calls above were expected, so the cleanup passes
	u.answer("y=1", "shell", "c.zsh")
	if err := s.PasteConfig(); err != nil {
		t.Fatal(err)
	}
	if cfgRead(t, s.ShellD+"/c.zsh") != "y=1\n" || !cfgLogged(u, "warn: zsh is not installed, so envsetup cannot check c.zsh.") {
		t.Errorf("c.zsh without zsh:\n%s", strings.Join(u.log, "\n"))
	}
}

// cfgRenamedRoot returns a copy of the repo's root whose lib/config.sh has these ENVSETUP_RENAMED items.
func cfgRenamedRoot(t *testing.T, root string, items ...string) string {
	t.Helper()
	dir := t.TempDir()
	entries, err := os.ReadDir(root)
	if err != nil {
		t.Fatal(err)
	}
	for _, e := range entries {
		if e.Name() != "lib" {
			if err := os.Symlink(filepath.Join(root, e.Name()), filepath.Join(dir, e.Name())); err != nil {
				t.Fatal(err)
			}
		}
	}
	cfgWrite(t, dir+"/lib/common.sh", cfgRead(t, root+"/lib/common.sh"))
	config := cfgRead(t, root+"/lib/config.sh")
	if !strings.Contains(config, "\nENVSETUP_RENAMED=()\n") {
		t.Fatal("lib/config.sh has no empty ENVSETUP_RENAMED=() line to replace")
	}
	config = strings.Replace(config, "\nENVSETUP_RENAMED=()\n", "\nENVSETUP_RENAMED=("+strings.Join(items, " ")+")\n", 1)
	cfgWrite(t, dir+"/lib/config.sh", config)
	return dir
}

func TestMigrateConfig(t *testing.T) {
	s, u, _ := cfgSetup(t)
	items := []string{"ENVSETUP_OLD_A=ENVSETUP_NEW_A", "ENVSETUP_OLD_B=ENVSETUP_NEW_B"}
	s.Root = cfgRenamedRoot(t, s.Root, items...)
	if got, err := s.renamed(); err != nil || !slices.Equal(got, items) {
		t.Fatalf("renamed = %q, %v; want %q", got, err, items)
	}

	// No config.sh: nothing to ask.
	if err := s.MigrateConfig(); err != nil || len(u.log) > 0 {
		t.Fatalf("MigrateConfig without config.sh: %v, %q", err, u.log)
	}
	text := "ENVSETUP_OLD_A=1\nENVSETUP_OLD_B+=(x) # ENVSETUP_OLD_AB stays\n"
	cfgWrite(t, s.UserConfig, text)

	// Dry run: describes the question with the real file and changes nothing.
	s.DryRun = true
	before := snapshotHome(t)
	if err := s.MigrateConfig(); err != nil {
		t.Fatal(err)
	}
	if d := diffSnapshots(before, snapshotHome(t)); len(d) > 0 {
		t.Errorf("the dry run changed HOME: %q", d)
	}
	list := " ENVSETUP_OLD_A → ENVSETUP_NEW_A ENVSETUP_OLD_B → ENVSETUP_NEW_B"
	if !cfgLogged(u, "note:   would ask to rename these settings in "+s.State+"/config.sh:"+list) {
		t.Errorf("the dry run did not describe the question:\n%s", strings.Join(u.log, "\n"))
	}
	s.DryRun = false

	// No keeps the old names.
	u.answer("no")
	if err := s.MigrateConfig(); err != nil {
		t.Fatal(err)
	}
	if cfgRead(t, s.UserConfig) != text || !cfgLoggedPrefix(u, "warn: envsetup keeps "+s.UserConfig+" as it is") {
		t.Errorf("no changed config.sh:\n%s", strings.Join(u.log, "\n"))
	}

	// First run: yes renames each item.
	u.answer("yes")
	if err := s.MigrateConfig(); err != nil {
		t.Fatal(err)
	}
	want := "ENVSETUP_NEW_A=1\nENVSETUP_NEW_B+=(x) # ENVSETUP_OLD_AB stays\n"
	if got := cfgRead(t, s.UserConfig); got != want {
		t.Errorf("config.sh = %q, want %q", got, want)
	}
	if !cfgLogged(u, "success: Renamed the settings in "+s.UserConfig+":"+list) {
		t.Errorf("no success message:\n%s", strings.Join(u.log, "\n"))
	}

	// Second run: no old name is left, so it asks nothing.
	n := len(u.log)
	if err := s.MigrateConfig(); err != nil || len(u.log) != n {
		t.Errorf("a second run: %v, %q", err, u.log[n:])
	}

	// Uninstall: yes keeps config.sh.
	cfgUninstall(t, s, u, "yes")
	if cfgRead(t, s.UserConfig) != want {
		t.Error("Uninstall with Keep: yes changed config.sh")
	}
}

// The rename goes through a link into the config repo, with a warning.
func TestMigrateConfigThroughLink(t *testing.T) {
	s, u, _ := cfgSetup(t)
	s.Root = cfgRenamedRoot(t, s.Root, "ENVSETUP_OLD_A=ENVSETUP_NEW_A")
	repoFile := s.Clone + "/config.sh"
	cfgWrite(t, repoFile, "ENVSETUP_OLD_A=1\n")
	if err := os.Symlink(repoFile, s.UserConfig); err != nil {
		t.Fatal(err)
	}
	u.answer("yes")
	if err := s.MigrateConfig(); err != nil {
		t.Fatal(err)
	}
	if cfgRead(t, repoFile) != "ENVSETUP_NEW_A=1\n" || !isLink(s.UserConfig) || !cfgLoggedPrefix(u, "warn: This config.sh is in your config repo.") {
		t.Errorf("repo file %q:\n%s", cfgRead(t, repoFile), strings.Join(u.log, "\n"))
	}
}

func TestMigrateConfigErrors(t *testing.T) {
	s, _, _ := cfgSetup(t)
	cfgWrite(t, s.UserConfig, "x=1\n")
	s.Root = t.TempDir() // no lib/config.sh
	if err := s.MigrateConfig(); err == nil {
		t.Error("MigrateConfig without lib/config.sh returned no error")
	}
}

// cfgRepo creates a git repo with these files and returns its path.
func cfgRepo(t *testing.T, f *fakes, files map[string]string) string {
	t.Helper()
	dir := t.TempDir()
	cfgGit(t, "init", "-q", dir)
	for name, text := range files {
		cfgWrite(t, dir+"/"+name, text)
	}
	cfgGit(t, "-C", dir, "add", "-A")
	cfgGit(t, "-C", dir, "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "--allow-empty", "-m", "init")
	cfgClearCalls(t, f)
	return dir
}

func TestSyncConfigRepo(t *testing.T) {
	s, u, f := cfgSetup(t)
	link := s.State + "/config.sh"

	// Without ENVSETUP_CONFIG_REPO and without a clone, it does nothing.
	if err := s.SyncConfigRepo(); err != nil || len(u.log) > 0 || len(f.calls()) > 0 {
		t.Fatalf("SyncConfigRepo without a repo: %v, %q, %q", err, u.log, f.calls())
	}

	src := cfgRepo(t, f, map[string]string{"config.sh": "ENVSETUP_SHELL=zsh\n"})
	t.Setenv("ENVSETUP_CONFIG_REPO", src)

	// Dry run: describes the clone and the link, and runs nothing.
	s.DryRun = true
	before := snapshotHome(t)
	if err := s.SyncConfigRepo(); err != nil {
		t.Fatal(err)
	}
	if d := diffSnapshots(before, snapshotHome(t)); len(d) > 0 {
		t.Errorf("the dry run changed HOME: %q", d)
	}
	if !cfgLogged(u, "note:   would clone "+src+" into "+s.Clone) || !cfgLogged(u, "note:   would link "+link+" to "+s.Clone+"/config.sh") {
		t.Errorf("the dry run did not describe the clone:\n%s", strings.Join(u.log, "\n"))
	}
	if c := f.calls(); len(c) > 0 {
		t.Errorf("the dry run ran %q", c)
	}
	s.DryRun = false

	// First run: clones and links.
	if err := s.SyncConfigRepo(); err != nil {
		t.Fatal(err)
	}
	if readlink(link) != s.Clone+"/config.sh" || cfgRead(t, link) != "ENVSETUP_SHELL=zsh\n" {
		t.Fatalf("config.sh links to %q and holds %q", readlink(link), cfgRead(t, link))
	}
	if c := f.calls(); len(c) != 1 || c[0] != "git clone -q -- "+src+" "+s.Clone {
		t.Errorf("calls = %q, want one git clone", c)
	}

	// Second run: asks to pull, and pulls on yes.
	cfgWrite(t, src+"/config.sh", "ENVSETUP_SHELL=bash\n")
	cfgGit(t, "-C", src, "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-qam", "bash")
	u.answer("yes")
	if err := s.SyncConfigRepo(); err != nil {
		t.Fatal(err)
	}
	if cfgRead(t, link) != "ENVSETUP_SHELL=bash\n" {
		t.Errorf("the pull did not update config.sh: %q", cfgRead(t, link))
	}
	// No pulls nothing.
	cfgClearCalls(t, f)
	u.answer("no")
	if err := s.SyncConfigRepo(); err != nil {
		t.Fatal(err)
	}
	if slices.ContainsFunc(f.calls(), func(c string) bool { return strings.Contains(c, " pull ") }) {
		t.Errorf("no still pulled: %q", f.calls())
	}
	// A dry run only says that it would ask.
	s.DryRun = true
	if err := s.SyncConfigRepo(); err != nil {
		t.Fatal(err)
	}
	if !cfgLogged(u, "note:   would ask to pull "+s.Clone) {
		t.Errorf("the dry run did not describe the pull:\n%s", strings.Join(u.log, "\n"))
	}
	s.DryRun = false

	// A failed pull shows a warning.
	cfgWrite(t, s.Clone+"/config.sh", "edited\n") // an edit in the clone blocks the pull
	cfgWrite(t, src+"/config.sh", "ENVSETUP_SHELL=zsh\n")
	cfgGit(t, "-C", src, "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-qam", "zsh")
	u.answer("yes")
	if err := s.SyncConfigRepo(); err != nil {
		t.Fatal(err)
	}
	if !cfgLoggedPrefix(u, "warn: Couldn't pull "+s.Clone+".") {
		t.Errorf("no warning for a failed pull:\n%s", strings.Join(u.log, "\n"))
	}
	cfgGit(t, "-C", s.Clone, "checkout", "-q", "config.sh")

	// Another ENVSETUP_CONFIG_REPO gets a warning, and the clone stays in use.
	t.Setenv("ENVSETUP_CONFIG_REPO", "/elsewhere")
	u.answer("no")
	if err := s.SyncConfigRepo(); err != nil {
		t.Fatal(err)
	}
	if !cfgLogged(u, "warn: ENVSETUP_CONFIG_REPO is /elsewhere, but "+s.Clone+" comes from "+src+". envsetup keeps using "+s.Clone+".") {
		t.Errorf("no warning for another URL:\n%s", strings.Join(u.log, "\n"))
	}
	cfgGit(t, "-C", s.Clone, "remote", "remove", "origin")
	u.answer("no")
	if err := s.SyncConfigRepo(); err != nil {
		t.Fatal(err)
	}
	if !cfgLoggedPrefix(u, "warn: ENVSETUP_CONFIG_REPO is /elsewhere, but "+s.Clone+" comes from an unknown URL.") {
		t.Errorf("no warning for a clone without origin:\n%s", strings.Join(u.log, "\n"))
	}
	t.Setenv("ENVSETUP_CONFIG_REPO", "")

	// A missing link is linked again.
	if err := os.Remove(link); err != nil {
		t.Fatal(err)
	}
	u.answer("no")
	if err := s.SyncConfigRepo(); err != nil {
		t.Fatal(err)
	}
	if readlink(link) != s.Clone+"/config.sh" {
		t.Errorf("the link was not made again: %q", readlink(link))
	}

	// Uninstall: no to the clone copies config.sh out of it, then yes keeps the copy.
	u.answer("yes", "no", "yes")
	if err := s.Uninstall(); err != nil {
		t.Fatalf("Uninstall: %v\n%s", err, strings.Join(u.log, "\n"))
	}
	if isDir(s.Clone) || isLink(link) || cfgRead(t, link) != "ENVSETUP_SHELL=bash\n" {
		t.Errorf("after Uninstall: clone %v, link %v, config.sh %q", isDir(s.Clone), isLink(link), cfgRead(t, link))
	}
}

// A config.sh of the user's own: yes keeps it, no moves it to config.sh.bak, unless that exists.
// A kept config.sh also stops later runs from asking to pull.
func TestSyncConfigRepoOwnConfig(t *testing.T) {
	for _, tc := range []struct {
		name, answer string
		bak          bool
		linked       bool
	}{
		{"keep", "yes", false, false},
		{"cancel keeps", cancel, false, false},
		{"replace", "no", false, true},
		{"replace with a .bak there", "no", true, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			s, u, f := cfgSetup(t)
			link := s.State + "/config.sh"
			src := cfgRepo(t, f, map[string]string{"config.sh": "repo=1\n"})
			t.Setenv("ENVSETUP_CONFIG_REPO", src)
			cfgWrite(t, link, "mine=1\n")
			if tc.bak {
				cfgWrite(t, link+".bak", "older=1\n")
			}
			u.answer(tc.answer)
			if err := s.SyncConfigRepo(); err != nil {
				t.Fatal(err)
			}
			if got := readlink(link) == s.Clone+"/config.sh"; got != tc.linked {
				t.Fatalf("linked = %v, want %v\n%s", got, tc.linked, strings.Join(u.log, "\n"))
			}
			if tc.linked {
				if cfgRead(t, link+".bak") != "mine=1\n" {
					t.Error("config.sh.bak does not hold the old config.sh")
				}
				return
			}
			if cfgRead(t, link) != "mine=1\n" {
				t.Errorf("config.sh = %q, want the user's own", cfgRead(t, link))
			}
			if tc.bak && !cfgLogged(u, "warn: "+link+".bak already exists, so envsetup keeps "+link+" as it is.") {
				t.Errorf("no warning about config.sh.bak:\n%s", strings.Join(u.log, "\n"))
			}
			// The next run neither asks nor pulls: it only reads the clone's origin.
			// A question would fail the test, because no answer is left.
			cfgClearCalls(t, f)
			want := []string{"git -C " + s.Clone + " remote get-url origin"}
			if err := s.SyncConfigRepo(); err != nil || !slices.Equal(f.calls(), want) {
				t.Errorf("a later run: %v, %q, want %q", err, f.calls(), want)
			}
		})
	}
}

func TestSyncConfigRepoFailures(t *testing.T) {
	s, u, f := cfgSetup(t)
	t.Setenv("ENVSETUP_CONFIG_REPO", "me")
	f.set("git", fakeCmd{Code: 128})
	if err := s.SyncConfigRepo(); err != nil {
		t.Fatal(err)
	}
	url := "https://github.com/me/envsetup-config"
	if !cfgLoggedPrefix(u, "warn: Couldn't clone "+url+".") || !slices.Equal(f.calls(), []string{"git clone -q -- " + url + " " + s.Clone}) {
		t.Errorf("a failed clone: %q\n%s", f.calls(), strings.Join(u.log, "\n"))
	}

	// A repo without config.sh links nothing.
	f.passThrough("git")
	src := cfgRepo(t, f, map[string]string{"README": "x\n"})
	t.Setenv("ENVSETUP_CONFIG_REPO", src)
	if err := s.SyncConfigRepo(); err != nil {
		t.Fatal(err)
	}
	if !cfgLogged(u, "warn: "+s.Clone+" has no config.sh, so envsetup links none.") || exists(s.State+"/config.sh") {
		t.Errorf("a repo without config.sh:\n%s", strings.Join(u.log, "\n"))
	}
}
