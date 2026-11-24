package setup

// This file holds tests that kill mutants that gremlins found alive (issue #202).
// Each test names the line that it checks, as gremlins reported it on the baseline run.

import (
	"os"
	"slices"
	"strings"
	"testing"
)

// config.go ShowWarning: a warning shows once, and an empty one never shows.
func TestShowWarning(t *testing.T) {
	u := newFakeUI(t)
	s := &Setup{UI: u}
	for _, w := range []string{"", "first", "first", "second", ""} {
		s.ShowWarning(w)
	}
	checkUILog(t, u.log, []string{"warn: first", "warn: second"})
}

// config.go cfgProfile and cfgMode: the values without a config, and with one.
func TestCfgProfileAndMode(t *testing.T) {
	for _, tc := range []struct {
		cfg           *Config
		profile, mode string
	}{
		{nil, "", "full"},
		{&Config{Profile: "home"}, "home", "full"},
		{&Config{Profile: "work", Mode: "lite"}, "work", "lite"},
	} {
		s := &Setup{Cfg: tc.cfg}
		if p, m := s.cfgProfile(), s.cfgMode(); p != tc.profile || m != tc.mode {
			t.Errorf("Cfg %+v: cfgProfile %q, cfgMode %q; want %q, %q", tc.cfg, p, m, tc.profile, tc.mode)
		}
	}
}

// config.go parseDump: a last item without a NUL counts, and a count past the end stops the parse.
func TestParseDumpBounds(t *testing.T) {
	if got := parseDump([]byte("A\x001\x00x")); len(got) != 1 || !slices.Equal(got["A"], []string{"x"}) {
		t.Errorf("parseDump without a last NUL = %q, want A=[x]", got)
	}
	// B claims 3 items, but only 2 fields follow it.
	got := parseDump([]byte("A\x000\x00B\x003\x00x\x00"))
	if a, ok := got["A"]; len(got) != 1 || !ok || len(a) != 0 {
		t.Errorf("parseDump with a count past the end = %q, want only an empty A", got)
	}
}

// main.go copyTree: it copies files and folders, follows links, and skips a link to nothing.
func TestCopyTree(t *testing.T) {
	src, dst := t.TempDir(), t.TempDir()
	writeTestFile(t, src+"/a", "a")
	if err := os.Chmod(src+"/a", 0o640); err != nil {
		t.Fatal(err)
	}
	writeTestFile(t, src+"/sub/b", "b")
	if err := os.Symlink(src+"/a", src+"/c"); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(src+"/gone", src+"/d"); err != nil {
		t.Fatal(err)
	}
	copyTree(src, dst)
	if readTestFile(t, dst+"/a") != "a" || readTestFile(t, dst+"/sub/b") != "b" || readTestFile(t, dst+"/c") != "a" {
		t.Error("copyTree did not copy a, sub/b and the link c")
	}
	if fi, err := os.Lstat(dst + "/c"); err != nil || !fi.Mode().IsRegular() {
		t.Error("copyTree copied the link c as a link, not as a file")
	}
	if fi, err := os.Stat(dst + "/a"); err != nil || fi.Mode().Perm() != 0o640 {
		t.Errorf("a has mode %v, want 0640", fi.Mode().Perm())
	}
	if exists(dst + "/d") {
		t.Error("copyTree copied a link to nothing")
	}
	copyTree(src+"/missing", dst) // a missing folder copies nothing, and does not panic
}

// installers.go and menu.go: the error from resolved_installers goes to stderr, and only when there is one.
func TestInstallersErrOnStderr(t *testing.T) {
	s, _, _ := menuSetup(t, "home", "full")
	s.Cfg.ResolvedInstallers = nil
	run := func() string {
		t.Helper()
		return menuCapture(t, &os.Stderr, func() { _ = s.RunInstallers() })
	}
	if got := run(); got != "" {
		t.Errorf("RunInstallers without an error printed %q to stderr", got)
	}
	s.Cfg.InstallersErr = "envsetup: no folder x"
	if got := run(); got != "envsetup: no folder x\n" {
		t.Errorf("RunInstallers printed %q to stderr, want the error", got)
	}
	if got := menuCapture(t, &os.Stderr, func() { s.profileLabel("home"); s.modeLabels() }); got != "" {
		t.Errorf("the labels printed %q to stderr", got)
	}
}

// packages.go: only dnf asks about EPEL.
func TestInstallPackagesNoEPELOnApt(t *testing.T) {
	s, _, f := newTestSetup(t, "home", "full")
	fakeOSRelease(t, s, map[string]string{"ID": "rocky", "ID_LIKE": "rhel centos fedora"})
	onlyManager(f, "apt")
	f.set("sudo", fakeCmd{Real: "/usr/bin/env"})
	f.set("rpm", fakeCmd{Code: 1})
	if err := s.InstallPackages(); err != nil {
		t.Fatal(err)
	}
	if c := pkgCalls(f, "rpm", "dnf"); len(c) > 0 {
		t.Errorf("apt checked EPEL: %q", c)
	}
}

// status.go newestTag: the highest tag wins, also when it is not the last line.
func TestNewestTagUnsorted(t *testing.T) {
	if got := newestTag("a\trefs/tags/v1.10.0\na\trefs/tags/v1.9.0\n"); got != "v1.10.0" {
		t.Errorf("newestTag = %q, want v1.10.0", got)
	}
}

// status.go verrevcmp: the first digit that differs decides, also when a later part says otherwise.
func TestVerrevcmpFirstDigit(t *testing.T) {
	if got := verrevcmp("v1.9.0", "v1.8.5"); got <= 0 {
		t.Errorf("verrevcmp(v1.9.0, v1.8.5) = %d, want > 0", got)
	}
	if got := versionCompare("v1.8.5", "v1.9.0"); got >= 0 {
		t.Errorf("versionCompare(v1.8.5, v1.9.0) = %d, want < 0", got)
	}
}

// link.go linkRC: a new block reports where it went.
func TestLinkRCReportsTheBlock(t *testing.T) {
	s, u, _ := newTestSetup(t, "home", "full")
	file := s.Home + "/.bashrc"
	if err := s.linkRC(file); err != nil {
		t.Fatal(err)
	}
	checkUILog(t, u.log, []string{"success: Linked shell config into " + file + ". Open a new shell to load it."})
}

// link.go dropCheckout: a no deletes the old checkout and says so.
func TestDropCheckoutDeletes(t *testing.T) {
	s, u, _ := newTestSetup(t, "home", "full")
	old := t.TempDir() + "/envsetup"
	writeTestFile(t, old+"/shell/init.sh", "")
	u.answer("no")
	if err := s.dropCheckout(old); err != nil {
		t.Fatal(err)
	}
	if exists(old) {
		t.Error("dropCheckout kept the checkout")
	}
	checkUILog(t, u.log, []string{"confirm: Keep " + old + "? New shells and updates no longer use it.", "success: Deleted " + old})
}

// zsh.go: with zsh, curl and chsh on PATH, SetUpZsh installs nothing, also in work lite.
func TestSetUpZshNothingMissing(t *testing.T) {
	s, u, f := newTestSetup(t, "home", "full")
	t.Setenv("SHELL", "/bin/zsh")
	writeTestFile(t, s.Home+"/.oh-my-zsh/oh-my-zsh.sh", "")
	if err := s.SetUpZsh(); err != nil {
		t.Fatal(err)
	}
	if slices.ContainsFunc(u.log, func(l string) bool { return strings.HasPrefix(l, "heading: Installing") }) {
		t.Errorf("SetUpZsh installed something: %q", u.log)
	}
	if c := f.calls(); len(c) > 0 {
		t.Errorf("SetUpZsh ran %q", c)
	}
}

func TestSetUpZshLiteNothingMissing(t *testing.T) {
	s, u, _ := newTestSetup(t, "work", "lite")
	s.DryRun = true
	t.Setenv("SHELL", "/bin/zsh")
	writeTestFile(t, s.Home+"/.oh-my-zsh/oh-my-zsh.sh", "")
	if err := s.SetUpZsh(); err != nil {
		t.Fatalf("SetUpZsh in work lite with nothing missing: %v, log %q", err, u.log)
	}
	if slices.ContainsFunc(u.log, func(l string) bool { return strings.Contains(l, "would install") && !strings.Contains(l, "oh-my-zsh") }) {
		t.Errorf("the dry run would install something: %q", u.log)
	}
}

// uninstall.go: a signing setting that is already gone (git exits 5) is not a failure.
func TestUninstallRemovesSigning(t *testing.T) {
	s, u, _ := uninstallTest(t)
	key := s.Home + "/.ssh/id_ed25519"
	writeTestFile(t, s.SSHMarker, "")
	// gpg.format and commit.gpgsign are gone already.
	writeTestFile(t, s.Home+"/.gitconfig", "[user]\n\tsigningkey = "+key+".pub\n")
	u.answer("yes")
	if err := s.Uninstall(); err != nil {
		t.Fatalf("Uninstall: %v, log %q", err, u.log)
	}
	if !slices.Contains(u.log, "success: Removed the settings that sign your commits with "+key) {
		t.Errorf("UI log = %q", u.log)
	}
	if got := readTestFile(t, s.Home+"/.gitconfig"); strings.Contains(got, "signingkey") || strings.Contains(got, "gpgsign") {
		t.Errorf(".gitconfig = %q, want the signing settings gone", got)
	}
}

// xdg.go xdgPlan: a note whose last line is the export, in a fence that never closes, is a move.
func TestXDGPlanUnclosedFence(t *testing.T) {
	s, _, _ := xdgSetup(t, xdgNote{"unc", "$HOME/.uncrc", "```\nexport UNCRC=$XDG_CONFIG_HOME/unc"})
	xdgWrite(t, s.Home+"/.uncrc", "x")
	skips, moves := s.xdgPlan()
	if len(skips) > 0 || len(moves) != 1 || moves[0].variable != "UNCRC" || moves[0].new != s.Home+"/.config/unc" {
		t.Errorf("skips %+v, moves %+v; want one move of UNCRC", skips, moves)
	}
}

// configedit.go SyncConfigRepo: a pull that works shows no warning, and a new link says so.
func TestSyncConfigRepoMessages(t *testing.T) {
	s, u, f := cfgSetup(t)
	src := cfgRepo(t, f, map[string]string{"config.sh": "x=1\n"})
	t.Setenv("ENVSETUP_CONFIG_REPO", src)
	if err := s.SyncConfigRepo(); err != nil {
		t.Fatal(err)
	}
	link := s.State + "/config.sh"
	if !cfgLogged(u, "success: Linked "+link+" to "+s.Clone+"/config.sh") {
		t.Errorf("no message about the link:\n%s", strings.Join(u.log, "\n"))
	}
	u.answer("yes")
	if err := s.SyncConfigRepo(); err != nil {
		t.Fatal(err)
	}
	if cfgLoggedPrefix(u, "warn: ") {
		t.Errorf("a pull that works gave a warning:\n%s", strings.Join(u.log, "\n"))
	}
}

// configedit.go addShellFile: a saved file says where it went.
func TestPasteConfigShellFileMessage(t *testing.T) {
	s, u, _ := cfgSetup(t)
	u.answer("x=1", "shell", "a")
	if err := s.PasteConfig(); err != nil {
		t.Fatal(err)
	}
	if !cfgLogged(u, "success: Saved "+s.ShellD+"/a.sh. New interactive shells load it.") {
		t.Errorf("no message about the file:\n%s", strings.Join(u.log, "\n"))
	}
}
