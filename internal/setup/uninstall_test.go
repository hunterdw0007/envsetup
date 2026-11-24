package setup

import (
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

// confirmUI records the default of each question, on top of the fake UI.
type confirmUI struct {
	*fakeUI
	defaultNo map[string]bool
}

func (c *confirmUI) Confirm(prompt string, defaultNo bool) (bool, bool) {
	c.defaultNo[prompt] = defaultNo
	return c.fakeUI.Confirm(prompt, defaultNo)
}

// uninstallTest returns a Setup with the real git on the sandbox's ~/.gitconfig.
func uninstallTest(t *testing.T) (*Setup, *fakeUI, *fakes) {
	t.Helper()
	s, u, f := newTestSetup(t, "home", "full")
	f.realGit()
	t.Setenv("HOSTNAME", "box")
	return s, u, f
}

// sshKeygen makes ssh-keygen a fake that writes a key, like the real one.
// Its arguments are -t ed25519 -C <comment> -f <key>.
func sshKeygen(t *testing.T, f *fakes) {
	t.Helper()
	script := filepath.Join(t.TempDir(), "ssh-keygen")
	writeTestFile(t, script, "#!/bin/sh\necho private >\"$6\"\necho \"ssh-ed25519 AAAA $4\" >\"$6.pub\"\n")
	if err := os.Chmod(script, 0o755); err != nil {
		t.Fatal(err)
	}
	f.set("ssh-keygen", fakeCmd{Real: script})
}

// TestUninstallAfterRunEverything checks that Uninstall undoes Run everything.
// Only the tools, the git identity and empty folders stay.
func TestUninstallAfterRunEverything(t *testing.T) {
	s, u, f := uninstallTest(t)
	f.set("brew", fakeCmd{})
	f.remove("gh")
	sshKeygen(t, f)
	// One installer stands in for all of them.
	// It installs a tool and records it, like a pinned installer.
	installer := filepath.Join(t.TempDir(), "tool.sh")
	writeTestFile(t, installer, `source "$ENVSETUP_ROOT/lib/common.sh"
mkdir -p "$HOME/.local/bin"
echo tool >"$HOME/.local/bin/tool"
envsetup::record_installed ohmyzsh
`)
	s.Cfg.ResolvedInstallers = []string{installer}
	writeTestFile(t, s.Home+"/.bashrc", "# mine\n")
	before := snapshotHome(t)

	u.answer("Me", "me@example.com", "yes")
	s.RunEverything()
	if slices.ContainsFunc(u.log, func(l string) bool { return strings.HasPrefix(l, "fail: ") }) {
		t.Fatalf("Run everything failed: %q", u.log)
	}
	for _, p := range []string{s.Data + "/shell/init.sh", s.GitFile, s.Installed, s.SSHMarker, s.Home + "/.ssh/id_ed25519"} {
		if !exists(p) {
			t.Errorf("Run everything did not create %s", p)
		}
	}

	u.answer("yes", "no")
	if err := s.Uninstall(); err != nil {
		t.Fatal(err)
	}
	after := snapshotHome(t)
	if got := after[s.Home+"/.local/bin/tool"]; got != "tool\n" {
		t.Errorf("Uninstall removed the tool: %q", got)
	}
	gitconfig := after[s.Home+"/.gitconfig"]
	if !strings.Contains(gitconfig, "name = Me") || !strings.Contains(gitconfig, "email = me@example.com") {
		t.Errorf("Uninstall removed the identity: %q", gitconfig)
	}
	if strings.Contains(gitconfig, "envsetup") || strings.Contains(gitconfig, "signingkey") {
		t.Errorf("Uninstall left envsetup's git settings: %q", gitconfig)
	}
	for _, p := range diffSnapshots(before, after) {
		switch {
		case p == s.Home+"/.gitconfig", strings.HasPrefix(p, s.Home+"/.local/bin"):
		case after[p] == "dir" && !strings.HasPrefix(p, s.Data) && !strings.HasPrefix(p, s.State):
			// Uninstall keeps empty folders that other programs share, such as ~/.local/share.
		default:
			t.Errorf("Uninstall left a change in %s", p)
		}
	}

	// A second Uninstall changes nothing.
	u.answer("yes")
	if err := s.Uninstall(); err != nil {
		t.Fatal(err)
	}
	if d := diffSnapshots(after, snapshotHome(t)); len(d) > 0 {
		t.Errorf("the second Uninstall changed %q", d)
	}
}

func TestUninstallFreshHome(t *testing.T) {
	s, u, _ := uninstallTest(t)
	before := snapshotHome(t)
	u.answer("yes")
	if err := s.Uninstall(); err != nil {
		t.Fatal(err)
	}
	if d := diffSnapshots(before, snapshotHome(t)); len(d) > 0 {
		t.Errorf("Uninstall on a fresh home changed %q", d)
	}
	if last := u.log[len(u.log)-1]; last != "plain: - your git user.name and user.email" {
		t.Errorf("last line = %q", last)
	}
}

func TestUninstallNo(t *testing.T) {
	s, u, _ := uninstallTest(t)
	writeTestFile(t, s.Data+"/shell/init.sh", "")
	before := snapshotHome(t)
	u.answer("no")
	if err := s.Uninstall(); err != ErrCancelled {
		t.Errorf("err = %v, want ErrCancelled", err)
	}
	if last := u.log[len(u.log)-1]; last != "plain: Uninstall removed nothing." {
		t.Errorf("last line = %q", last)
	}
	if d := diffSnapshots(before, snapshotHome(t)); len(d) > 0 {
		t.Errorf("a no changed %q", d)
	}
}

// userFiles creates everything that Uninstall asks about.
func userFiles(t *testing.T, s *Setup) {
	t.Helper()
	writeTestFile(t, s.Clone+"/config.sh", "# repo\n")
	writeTestFile(t, s.UserConfig, "# mine\n")
	writeTestFile(t, s.ShellD+"/mine.sh", "# mine\n")
	writeTestFile(t, s.Home+"/.ssh/id_ed25519", "private\n")
	writeTestFile(t, s.Home+"/.ssh/id_ed25519.pub", "public\n")
	writeTestFile(t, s.SSHMarker, "")
	writeTestFile(t, s.ChshMarker, "")
	writeTestFile(t, s.State+"/config.sh.bak", "# old\n")
	writeTestFile(t, s.Home+"/.oh-my-zsh/oh-my-zsh.sh", "")
	t.Setenv("SHELL", "/bin/zsh")
}

var keepQuestions = []string{
	"Keep %s? It is the clone of your own config repo.",
	"Keep your own config (%s)?",
	"Keep %s? It holds your own shell files.",
	"Keep ~/.ssh/id_ed25519? It is this machine's SSH key.",
	"Keep zsh as your login shell?",
}

// TestUninstallKeepsByDefault checks that each "Keep …?" question keeps the item on its default and on a cancel.
func TestUninstallKeepsByDefault(t *testing.T) {
	s, u, f := uninstallTest(t)
	c := &confirmUI{fakeUI: u, defaultNo: map[string]bool{}}
	s.UI = c
	userFiles(t, s)
	before := snapshotHome(t)
	u.answer("yes", cancel, cancel, cancel, cancel, cancel)
	if err := s.Uninstall(); err != nil {
		t.Fatal(err)
	}
	asked := 0
	for prompt, defaultNo := range c.defaultNo {
		if strings.HasPrefix(prompt, "Keep ") {
			asked++
			if defaultNo {
				t.Errorf("%q starts on No", prompt)
			}
		}
	}
	if asked != len(keepQuestions) {
		t.Errorf("asked %d Keep questions, want %d: %v", asked, len(keepQuestions), c.defaultNo)
	}
	after := snapshotHome(t)
	for _, p := range []string{s.Clone + "/config.sh", s.UserConfig, s.ShellD + "/mine.sh", s.Home + "/.ssh/id_ed25519", s.State + "/config.sh.bak"} {
		if after[p] != before[p] {
			t.Errorf("Uninstall did not keep %s", p)
		}
	}
	for _, want := range []string{
		"plain: - your config repo: " + s.Clone,
		"plain: - your config: " + s.UserConfig,
		"plain: - your shell files: " + s.ShellD,
		"plain: - your SSH key: " + s.Home + "/.ssh/id_ed25519",
		"plain: - zsh as your login shell",
		"plain: - your old config: " + s.State + "/config.sh.bak",
		"plain: - oh-my-zsh: remove it with uninstall_oh_my_zsh",
	} {
		if !slices.Contains(u.log, want) {
			t.Errorf("UI log has no %q", want)
		}
	}
	if c := f.calls(); slices.ContainsFunc(c, func(c string) bool { return strings.HasPrefix(c, "chsh") }) {
		t.Errorf("a cancel ran chsh: %q", c)
	}
}

// TestUninstallRemovesOnNo checks that a no to each "Keep …?" question removes the item.
func TestUninstallRemovesOnNo(t *testing.T) {
	s, u, f := uninstallTest(t)
	f.set("chsh", fakeCmd{})
	userFiles(t, s)
	// A config.sh that links into the clone becomes a copy before the clone goes.
	if err := os.Remove(s.UserConfig); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(s.Clone+"/config.sh", s.UserConfig); err != nil {
		t.Fatal(err)
	}
	u.answer("yes", "no", "yes", "no", "no", "no")
	if err := s.Uninstall(); err != nil {
		t.Fatal(err)
	}
	for _, p := range []string{s.Clone, s.ShellD, s.Home + "/.ssh"} {
		if exists(p) {
			t.Errorf("Uninstall left %s", p)
		}
	}
	if isLink(s.UserConfig) || readTestFile(t, s.UserConfig) != "# repo\n" {
		t.Error("config.sh did not become a copy of the clone's file")
	}
	bash, _ := exec.LookPath("bash")
	if !slices.Contains(f.calls(), "chsh -s "+bash) {
		t.Errorf("calls = %q, want chsh back to bash", f.calls())
	}
}

func TestUninstallDryRun(t *testing.T) {
	s, u, f := uninstallTest(t)
	f.set("chsh", fakeCmd{})
	userFiles(t, s)
	writeTestFile(t, s.Home+"/.bashrc", "a\n"+RCBegin+"\n"+RCEnd+"\n")
	writeTestFile(t, s.GitFile, "")
	writeTestFile(t, s.Home+"/.gitconfig", "[include]\n\tpath = "+s.GitFile+"\n[user]\n\tsigningkey = "+s.Home+"/.ssh/id_ed25519.pub\n")
	writeTestFile(t, s.Data+"/shell/init.sh", "")
	s.DryRun = true
	before := snapshotHome(t)
	u.answer("yes", "no", "no", "no", "no", "no")
	if err := s.Uninstall(); err != nil {
		t.Fatal(err)
	}
	if d := diffSnapshots(before, snapshotHome(t)); len(d) > 0 {
		t.Errorf("the dry run changed %q", d)
	}
	for _, want := range []string{
		"note:   would remove the envsetup block from " + s.Home + "/.bashrc",
		"note:   would remove the include of " + s.GitFile + " from ~/.gitconfig",
		"note:   would remove the settings that sign your commits with " + s.Home + "/.ssh/id_ed25519 from ~/.gitconfig",
		"note:   would delete " + s.GitFile,
		"note:   would delete " + s.Data,
		"note:   would delete " + s.Clone,
		"note:   would delete " + s.UserConfig,
		"note:   would delete " + s.ShellD,
		"note:   would delete " + s.Home + "/.ssh/id_ed25519 and " + s.Home + "/.ssh/id_ed25519.pub",
		"note:   would change your login shell back to bash (chsh)",
	} {
		if !slices.Contains(u.log, want) {
			t.Errorf("UI log has no %q", want)
		}
	}
	// The dry run only reads git settings.
	want := []string{"git config --global --get-all include.path", "git config --global user.signingkey"}
	if c := f.calls(); !slices.Equal(c, want) {
		t.Errorf("the dry run ran %q, want %q", c, want)
	}

	// An empty shell.d gets its own line.
	if err := os.Remove(s.ShellD + "/mine.sh"); err != nil {
		t.Fatal(err)
	}
	u.log = nil
	u.answer("yes", "yes", "yes", "yes", "yes")
	if err := s.Uninstall(); err != nil {
		t.Fatal(err)
	}
	if !slices.Contains(u.log, "note:   would delete the empty "+s.ShellD) {
		t.Errorf("UI log = %q", u.log)
	}
}

// brokenGit makes git exit 4 when its arguments contain part.
// Every other call runs the real git.
func brokenGit(t *testing.T, f *fakes, part string) {
	t.Helper()
	script := filepath.Join(t.TempDir(), "git")
	writeTestFile(t, script, "#!/bin/sh\ncase \"$*\" in *'"+part+"'*) exit 4;; esac\nexec '"+f.cmds["git"].Real+"' \"$@\"\n")
	if err := os.Chmod(script, 0o755); err != nil {
		t.Fatal(err)
	}
	f.set("git", fakeCmd{Real: script})
}

// TestUninstallFailures checks that a failed step shows its error, and the other steps still run.
func TestUninstallFailures(t *testing.T) {
	for _, tc := range []struct {
		name, want string
		answers    []string
		setUp      func(t *testing.T, s *Setup, f *fakes)
	}{
		{"startup file", "fail: Couldn't edit %s/.bashrc", []string{"yes"}, func(t *testing.T, s *Setup, f *fakes) {
			writeTestFile(t, s.Home+"/.bashrc", RCBegin+"\n"+RCEnd+"\n")
			os.Chmod(s.Home+"/.bashrc", 0o444)
		}},
		{"include", "fail: Couldn't edit ~/.gitconfig", []string{"yes"}, func(t *testing.T, s *Setup, f *fakes) {
			writeTestFile(t, s.Home+"/.gitconfig", "[include]\n\tpath = "+s.GitFile+"\n")
			brokenGit(t, f, "--unset-all include.path")
		}},
		{"signing", "fail: Couldn't remove the settings that sign your commits from ~/.gitconfig", []string{"yes"}, func(t *testing.T, s *Setup, f *fakes) {
			writeTestFile(t, s.SSHMarker, "")
			writeTestFile(t, s.Home+"/.gitconfig", "[user]\n\tsigningkey = "+s.Home+"/.ssh/id_ed25519.pub\n")
			brokenGit(t, f, "--unset-all gpg.format")
		}},
		{"chsh", "fail: Couldn't change your login shell", []string{"yes", "no"}, func(t *testing.T, s *Setup, f *fakes) {
			writeTestFile(t, s.ChshMarker, "")
			t.Setenv("SHELL", "/bin/zsh")
			f.set("chsh", fakeCmd{Code: 1})
		}},
		{"copy out of the clone", "fail: Couldn't copy %s/.config/envsetup/config.sh out of %s/.config/envsetup/repo, so uninstall keeps the clone", []string{"yes", "no", "yes"}, func(t *testing.T, s *Setup, f *fakes) {
			writeTestFile(t, s.Clone+"/config.sh", "")
			os.Symlink(s.Clone+"/config.sh", s.UserConfig)
			f.set("cp", fakeCmd{Code: 1})
		}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if os.Geteuid() == 0 && tc.name == "startup file" {
				t.Skip("root writes anyway")
			}
			s, u, f := uninstallTest(t)
			tc.setUp(t, s, f)
			u.answer(tc.answers...)
			if err := s.Uninstall(); err != ErrFailed {
				t.Errorf("err = %v, want ErrFailed", err)
			}
			want := strings.ReplaceAll(tc.want, "%s", s.Home)
			if !slices.Contains(u.log, want) {
				t.Errorf("UI log = %q, want %q", u.log, want)
			}
		})
	}
}

func TestRmdir(t *testing.T) {
	dir := t.TempDir()
	writeTestFile(t, dir+"/full/mine", "x")
	if err := os.Mkdir(dir+"/empty", 0o755); err != nil {
		t.Fatal(err)
	}
	rmdir(dir+"/full", true)
	rmdir(dir+"/full", false)
	rmdir(dir+"/empty", false)
	if !isFile(dir + "/full/mine") {
		t.Error("rmdir removed a folder with a file in it")
	}
	if exists(dir + "/empty") {
		t.Error("rmdir kept an empty folder")
	}
}

// TestUninstallKeepsUserFilesInState checks that the state folder stays when it holds a file of the user's own.
func TestUninstallKeepsUserFilesInState(t *testing.T) {
	s, u, _ := uninstallTest(t)
	writeTestFile(t, s.State+"/profile", "home\n")
	writeTestFile(t, s.State+"/notes.txt", "mine\n")
	u.answer("yes")
	if err := s.Uninstall(); err != nil {
		t.Fatal(err)
	}
	if exists(s.State + "/profile") {
		t.Error("Uninstall kept the saved profile")
	}
	if got := readTestFile(t, s.State+"/notes.txt"); got != "mine\n" {
		t.Errorf("notes.txt = %q", got)
	}
}

func TestFileHasLine(t *testing.T) {
	file := filepath.Join(t.TempDir(), "f")
	writeTestFile(t, file, "a\nbb\n")
	if !fileHasLine(file, "bb") || fileHasLine(file, "b") || fileHasLine(file+".missing", "a") {
		t.Error("fileHasLine does not match whole lines of a file that exists")
	}
}
