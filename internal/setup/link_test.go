package setup

import (
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

func TestLinkShellConfigDryRun(t *testing.T) {
	s, u, f := newTestSetup(t, "home", "full")
	s.DryRun = true
	writeTestFile(t, s.Home+"/.bashrc", "# mine\n")
	before := snapshotHome(t)
	if err := s.LinkShellConfig(); err != nil {
		t.Fatal(err)
	}
	checkUILog(t, u.log, []string{
		"note:   would copy shell/ (v0.0.0-test) to " + s.Data + ", which new shells load",
		"note:   would create " + s.ShellD + " for your own shell files",
		"note:   would add a 5-line block to " + s.Home + "/.bashrc that loads shell/ from " + s.Data,
	})
	if d := diffSnapshots(before, snapshotHome(t)); len(d) > 0 {
		t.Errorf("the dry run changed HOME: %q", d)
	}
	if c := f.calls(); len(c) > 0 {
		t.Errorf("the dry run ran %q", c)
	}
}

// TestLinkShellConfigRuns covers the first run, the second run and Uninstall.
func TestLinkShellConfigRuns(t *testing.T) {
	s, u, f := newTestSetup(t, "home", "full")
	f.realGit()
	const mine = "alias a=b\nalias c=d\n"
	writeTestFile(t, s.Home+"/.bashrc", mine)
	before := snapshotHome(t)

	if err := s.LinkShellConfig(); err != nil {
		t.Fatal(err)
	}
	block, _ := rcBlock(s.Data, s.State, s.Home)
	if got := readTestFile(t, s.Home+"/.bashrc"); got != mine+block {
		t.Errorf(".bashrc after the first run:\n%s", got)
	}
	if got := readTestFile(t, s.Data+"/version"); got != "v0.0.0-test\n" {
		t.Errorf("version = %q", got)
	}
	if readTestFile(t, s.Data+"/shell/init.sh") != readTestFile(t, s.Root+"/shell/init.sh") {
		t.Error("the copy of shell/init.sh differs from the repo")
	}
	if !isDir(s.ShellD) {
		t.Error("no shell.d")
	}
	if exists(s.Home + "/.zshrc") {
		t.Error("SHELL=/bin/bash linked .zshrc")
	}
	if c := f.calls(); len(c) > 0 {
		t.Errorf("the first run ran %q", c)
	}
	first := snapshotHome(t)

	u.log = nil
	if err := s.LinkShellConfig(); err != nil {
		t.Fatal(err)
	}
	checkUILog(t, u.log, []string{
		"success: Copied shell config (v0.0.0-test) to " + s.Data,
		"warn: Already linked in " + s.Home + "/.bashrc",
	})
	if d := diffSnapshots(first, snapshotHome(t)); len(d) > 0 {
		t.Errorf("the second run changed %q", d)
	}

	u.answer("yes")
	if err := s.Uninstall(); err != nil {
		t.Fatal(err)
	}
	after := snapshotHome(t)
	if got := after[s.Home+"/.bashrc"]; got != mine {
		t.Errorf(".bashrc after Uninstall = %q, want %q", got, mine)
	}
	// Uninstall keeps the empty XDG folders, such as ~/.local/share.
	for _, d := range diffSnapshots(before, after) {
		if after[d] != "dir" || strings.HasPrefix(d, s.Data) || strings.HasPrefix(d, s.State) {
			t.Errorf("Uninstall left %s", d)
		}
	}
}

// TestLinkRCNoFinalNewline checks that a .bashrc without a final newline keeps all of its lines.
// Today linkRC adds the block to the end of the last line.
// Uninstall then cannot find the block.
func TestLinkRCNoFinalNewline(t *testing.T) {
	t.Skip("bug: linkRC adds the block to a last line without a newline (no issue yet)")
	s, u, f := newTestSetup(t, "home", "full")
	f.realGit()
	writeTestFile(t, s.Home+"/.bashrc", "alias a=b")
	if err := s.linkRC(s.Home + "/.bashrc"); err != nil {
		t.Fatal(err)
	}
	block, _ := rcBlock(s.Data, s.State, s.Home)
	if got := readTestFile(t, s.Home+"/.bashrc"); got != "alias a=b\n"+block {
		t.Errorf(".bashrc = %q", got)
	}
	u.answer("yes")
	if err := s.Uninstall(); err != nil {
		t.Fatal(err)
	}
	if got := readTestFile(t, s.Home+"/.bashrc"); got != "alias a=b\n" {
		t.Errorf(".bashrc after Uninstall = %q", got)
	}
}

func TestLinkShellConfigZshLoginShell(t *testing.T) {
	s, _, _ := newTestSetup(t, "home", "full")
	t.Setenv("SHELL", "/bin/zsh")
	if err := s.LinkShellConfig(); err != nil {
		t.Fatal(err)
	}
	block, _ := rcBlock(s.Data, s.State, s.Home)
	for _, rc := range []string{"/.bashrc", "/.zshrc"} {
		if got := readTestFile(t, s.Home+rc); got != block {
			t.Errorf("%s = %q, want the block", rc, got)
		}
	}
}

// TestLinkShellConfigZsh opts in to zsh with ENVSETUP_SHELL=zsh.
func TestLinkShellConfigZsh(t *testing.T) {
	s, u, f := newTestSetup(t, "home", "full")
	writeTestFile(t, s.UserConfig, "ENVSETUP_SHELL=zsh\n")
	f.passThrough("git") // the load reads git/gitconfig
	cfg, err := s.Load("home", "full", s.UserConfig, true)
	if err != nil || cfg.Shell != "zsh" {
		t.Fatalf("Load = %+v, %v", cfg, err)
	}
	s.Cfg = cfg
	commit, err := s.Pin("ohmyzsh")
	if err != nil || commit == "" {
		t.Fatalf("Pin(ohmyzsh) = %q, %v", commit, err)
	}
	// The installer writes the variables that envsetup passes, so the test can check them.
	f.set("curl", fakeCmd{Out: `mkdir "$HOME/.oh-my-zsh" && echo "$RUNZSH $CHSH $KEEP_ZSHRC" >"$HOME/.oh-my-zsh/env"`})
	f.set("chsh", fakeCmd{})
	u.answer("yes")
	if err := s.LinkShellConfig(); err != nil {
		t.Fatal(err)
	}
	want := []string{
		"chsh -s " + f.bin + "/zsh",
		"curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/" + commit + "/tools/install.sh",
	}
	if c := slices.DeleteFunc(f.calls(), func(c string) bool { return strings.HasPrefix(c, "git ") }); !slices.Equal(c, want) {
		t.Errorf("calls = %q, want %q", c, want)
	}
	if got := readTestFile(t, s.Home+"/.oh-my-zsh/env"); got != "no no yes\n" {
		t.Errorf("installer env = %q, want RUNZSH=no CHSH=no KEEP_ZSHRC=yes", got)
	}
	if !isFile(s.ChshMarker) {
		t.Error("no chsh marker")
	}
	block, _ := rcBlock(s.Data, s.State, s.Home)
	if got := readTestFile(t, s.Home+"/.zshrc"); got != block {
		t.Errorf(".zshrc = %q", got)
	}

	// The second run asks again, because SHELL is still bash, but it installs nothing.
	u.answer("no")
	n := len(f.calls())
	if err := s.LinkShellConfig(); err != nil {
		t.Fatal(err)
	}
	if c := f.calls()[n:]; len(c) > 0 {
		t.Errorf("the second run ran %q", c)
	}
}

func TestInstallZshInstallsMissing(t *testing.T) {
	s, u, f := newTestSetup(t, "home", "full")
	t.Setenv("SHELL", "/bin/zsh")
	writeTestFile(t, s.Home+"/.oh-my-zsh/oh-my-zsh.sh", "")
	f.remove("zsh")
	f.remove("chsh")
	f.set("brew", fakeCmd{})
	if err := s.SetUpZsh(); err != nil {
		t.Fatal(err)
	}
	// packages/names.txt says that brew needs no package for chsh.
	if c := f.calls(); !slices.Equal(c, []string{"brew install zsh"}) {
		t.Errorf("calls = %q, want brew install zsh", c)
	}
	if !slices.Contains(u.log, "heading: Installing zsh chsh...") {
		t.Errorf("UI log = %q", u.log)
	}
}

func TestInstallZshFailures(t *testing.T) {
	t.Run("lite", func(t *testing.T) {
		s, u, f := newTestSetup(t, "work", "lite")
		f.remove("zsh")
		if err := s.SetUpZsh(); err != ErrFailed {
			t.Errorf("err = %v, want ErrFailed", err)
		}
		checkUILog(t, u.log, []string{"fail: work (lite) does not assume sudo, so it cannot install zsh. Install it yourself, then run this again."})
	})
	t.Run("no package manager", func(t *testing.T) {
		s, u, f := newTestSetup(t, "home", "full")
		for _, m := range []string{"zsh", "brew", "apt-get", "dnf", "zypper", "pacman", "apk", "nix-env"} {
			f.remove(m)
		}
		if err := s.SetUpZsh(); err != ErrFailed {
			t.Errorf("err = %v, want ErrFailed", err)
		}
		checkUILog(t, u.log, []string{"fail: envsetup found no supported package manager to install zsh."})
	})
	t.Run("failed install", func(t *testing.T) {
		s, _, f := newTestSetup(t, "home", "full")
		f.remove("zsh")
		f.set("brew", fakeCmd{Code: 1})
		if err := s.SetUpZsh(); exitCode(err) != 1 {
			t.Errorf("err = %v, want exit 1", err)
		}
		if exists(s.Home + "/.zshrc") {
			t.Error("a failed install linked .zshrc")
		}
	})
	t.Run("failed download", func(t *testing.T) {
		s, u, f := newTestSetup(t, "home", "full")
		t.Setenv("SHELL", "/bin/zsh")
		f.set("curl", fakeCmd{Code: 22})
		if err := s.SetUpZsh(); err != ErrFailed {
			t.Errorf("err = %v, want ErrFailed", err)
		}
		if !slices.Contains(u.log, "fail: Couldn't download the oh-my-zsh installer.") {
			t.Errorf("UI log = %q", u.log)
		}
	})
	t.Run("failed chsh", func(t *testing.T) {
		s, u, f := newTestSetup(t, "home", "full")
		writeTestFile(t, s.Home+"/.oh-my-zsh/oh-my-zsh.sh", "")
		f.set("chsh", fakeCmd{Code: 1})
		u.answer("yes")
		if err := s.SetUpZsh(); err != nil {
			t.Fatal(err)
		}
		if exists(s.ChshMarker) {
			t.Error("a failed chsh wrote the marker")
		}
	})
	t.Run("marker folder is a file", func(t *testing.T) {
		s, u, f := newTestSetup(t, "home", "full")
		writeTestFile(t, s.Home+"/.oh-my-zsh/oh-my-zsh.sh", "")
		writeTestFile(t, s.State, "")
		f.set("chsh", fakeCmd{})
		u.answer("yes")
		if err := s.SetUpZsh(); err == nil {
			t.Error("no error when the marker cannot be written")
		}
	})
}

// TestCopyShellKeepsOldCopy checks that a failed cp leaves the old copy of shell/ in place.
func TestCopyShellKeepsOldCopy(t *testing.T) {
	t.Skip("#160")
	s, _, f := newTestSetup(t, "home", "full")
	writeTestFile(t, s.Data+"/shell/init.sh", "# old\n")
	f.set("cp", fakeCmd{Code: 1})
	if err := s.copyShell(); err == nil {
		t.Error("no error from a failed cp")
	}
	if got := readTestFile(t, s.Data+"/shell/init.sh"); got != "# old\n" {
		t.Errorf("init.sh = %q, want the old copy", got)
	}
}

func TestCopyShellErrors(t *testing.T) {
	s, _, f := newTestSetup(t, "home", "full")
	writeTestFile(t, filepath.Dir(s.Data), "") // a file where the folder should be
	if err := s.LinkShellConfig(); err == nil {
		t.Error("no error when the data folder cannot be created")
	}
	if err := os.Remove(filepath.Dir(s.Data)); err != nil {
		t.Fatal(err)
	}
	f.set("cp", fakeCmd{Code: 1})
	if err := s.copyShell(); exitCode(err) != 1 {
		t.Errorf("err = %v, want exit 1 from cp", err)
	}
	if exists(s.Data + "/version") {
		t.Error("a failed copy wrote the version")
	}
	f.set("cp", fakeCmd{})
	if err := os.MkdirAll(s.Data+"/version", 0o755); err != nil {
		t.Fatal(err)
	}
	if err := s.copyShell(); err == nil {
		t.Error("no error when the version file cannot be written")
	}
}

// TestLinkShellConfigErrors checks that each step returns its error.
// A folder where a file should be makes the step fail.
func TestLinkShellConfigErrors(t *testing.T) {
	for _, tc := range []struct {
		name  string
		setUp func(t *testing.T, s *Setup, f *fakes)
		run   func(s *Setup) error
	}{
		{"shell.d", func(t *testing.T, s *Setup, f *fakes) { writeTestFile(t, s.State, "") }, (*Setup).LinkShellConfig},
		{".bashrc", func(t *testing.T, s *Setup, f *fakes) { mkdirTest(t, s.Home+"/.bashrc") }, (*Setup).LinkShellConfig},
		{".zshrc of the login shell", func(t *testing.T, s *Setup, f *fakes) {
			t.Setenv("SHELL", "/bin/zsh")
			mkdirTest(t, s.Home+"/.zshrc")
		}, (*Setup).LinkShellConfig},
		{"zsh install", func(t *testing.T, s *Setup, f *fakes) {
			s.Cfg.Shell, s.Cfg.Profile, s.Cfg.Mode = "zsh", "work", "lite"
			f.remove("zsh")
		}, (*Setup).LinkShellConfig},
		{"copy in SetUpZsh", func(t *testing.T, s *Setup, f *fakes) {
			t.Setenv("SHELL", "/bin/zsh")
			writeTestFile(t, s.Home+"/.oh-my-zsh/oh-my-zsh.sh", "")
			writeTestFile(t, filepath.Dir(s.Data), "")
		}, (*Setup).SetUpZsh},
	} {
		t.Run(tc.name, func(t *testing.T) {
			s, _, f := newTestSetup(t, "home", "full")
			tc.setUp(t, s, f)
			if err := tc.run(s); err == nil {
				t.Error("no error")
			}
		})
	}
}

// mkdirTest creates a folder where the action expects a file.
func mkdirTest(t *testing.T, dir string) {
	t.Helper()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
}

// oldBlock is a block of an older release that loaded shell/ from a checkout.
func oldBlock(dir string) string {
	return RCBegin + "\nexport ENVSETUP_ROOT=" + Quote(dir) + "\nsource \"$ENVSETUP_ROOT/shell/init.sh\"\n" + RCEnd + "\n"
}

func TestLinkRCRewritesOldBlock(t *testing.T) {
	for _, tc := range []struct {
		name, answer string
		dryRun, kept bool
	}{
		{"keep", "yes", false, true},
		{"cancel keeps", cancel, false, true},
		{"delete", "no", false, false},
		{"dry run", "no", true, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			s, u, _ := newTestSetup(t, "home", "full")
			s.DryRun = tc.dryRun
			checkout := s.Home + "/my envsetup"
			writeTestFile(t, checkout+"/shell/init.sh", "")
			writeTestFile(t, s.Home+"/.bashrc", "a\n"+oldBlock(checkout)+"b\n")
			u.answer(tc.answer)
			if err := s.linkRC(s.Home + "/.bashrc"); err != nil {
				t.Fatal(err)
			}
			if isDir(checkout) != tc.kept {
				t.Errorf("checkout kept = %v, want %v", isDir(checkout), tc.kept)
			}
			block, _ := rcBlock(s.Data, s.State, s.Home)
			want := "a\n" + block + "b\n"
			if tc.dryRun {
				want = "a\n" + oldBlock(checkout) + "b\n"
				checkUILog(t, u.log, []string{
					"note:   would rewrite the envsetup block in " + s.Home + "/.bashrc to load shell/ from " + s.Data,
					"confirm: Keep " + checkout + "? New shells and updates no longer use it.",
					"note:   would delete " + checkout,
				})
			}
			if got := readTestFile(t, s.Home+"/.bashrc"); got != want {
				t.Errorf(".bashrc = %q, want %q", got, want)
			}
			// A second link of the same file asks nothing, because the block is current or was asked about.
			if !tc.dryRun {
				if err := s.linkRC(s.Home + "/.bashrc"); err != nil {
					t.Fatal(err)
				}
				if got := u.log[len(u.log)-1]; got != "warn: Already linked in "+s.Home+"/.bashrc" {
					t.Errorf("second run: %q", got)
				}
			}
		})
	}
}

func TestDropCheckoutOfThisRun(t *testing.T) {
	s, u, _ := newTestSetup(t, "home", "full")
	writeTestFile(t, s.Home+"/.bashrc", oldBlock(s.Root))
	if err := s.linkRC(s.Home + "/.bashrc"); err != nil {
		t.Fatal(err)
	}
	want := "plain: New shells no longer load " + s.Root + ". You can delete it after setup ends. Keep it if you work on envsetup there."
	if !slices.Contains(u.log, want) {
		t.Errorf("UI log = %q, want %q", u.log, want)
	}
	if !isFile(s.Root + "/shell/init.sh") {
		t.Fatal("the repo lost shell/init.sh")
	}
}

func TestOldRoot(t *testing.T) {
	s, _, _ := newTestSetup(t, "home", "full")
	for _, tc := range []struct{ text, want string }{
		{oldBlock("/a b/$c"), "/a b/$c"},
		{"no block\n", ""},
		{"export ENVSETUP_ROOT=$(exit 3)x\nexit 3\n", "x"},
		{"export ENVSETUP_ROOT=\"\n", ""}, // bash fails on the open quote
	} {
		if got := s.oldRoot(tc.text); got != tc.want {
			t.Errorf("oldRoot(%q) = %q, want %q", tc.text, got, tc.want)
		}
	}
}

func TestLinkRCErrors(t *testing.T) {
	s, _, _ := newTestSetup(t, "home", "full")
	if err := s.linkRC(s.Home + "/no/such/folder/.bashrc"); err == nil {
		t.Error("no error for a startup file in a missing folder")
	}
	checkout := s.Home + "/old"
	writeTestFile(t, checkout+"/shell/init.sh", "")
	writeTestFile(t, s.Home+"/.bashrc", oldBlock(checkout))
	if err := os.Chmod(s.Home+"/.bashrc", 0o444); err != nil {
		t.Fatal(err)
	}
	if os.Geteuid() != 0 { // root writes anyway
		if err := s.linkRC(s.Home + "/.bashrc"); err == nil {
			t.Error("no error for a read-only startup file")
		}
	}
}
