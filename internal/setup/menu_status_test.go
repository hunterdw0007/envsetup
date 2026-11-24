package setup

// This file tests the menu, RunStep and Status (issue #192).

import (
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

// menuSetup returns a Setup whose git runs for real, on a home with no envsetup yet.
// ENVSETUP_REPO_URL names a folder that is not there, so newestRelease stays on this machine.
// apt is the only package manager, and dpkg-query reports each package as installed.
func menuSetup(t *testing.T, profile, mode string) (*Setup, *fakeUI, *fakes) {
	t.Helper()
	t.Setenv("ENVSETUP_REPO_URL", filepath.Join(t.TempDir(), "no-repo"))
	t.Setenv("EDITOR", "true")
	// Under -race, each fake waits 1 s when it exits, and Status runs one fake for each package.
	// atexit_sleep_ms=0 drops that wait.
	t.Setenv("GORACE", "atexit_sleep_ms=0")
	s, u, f := newTestSetup(t, profile, mode)
	f.passThrough("git")
	for _, m := range []string{"brew", "dnf", "zypper", "pacman", "apk", "nix-env"} {
		f.remove(m)
	}
	f.set("apt-get", fakeCmd{})
	f.set("dpkg-query", fakeCmd{Out: "install ok installed"})
	return s, u, f
}

// menuCapture returns what fn writes to the file that *std points to, such as os.Stdout.
func menuCapture(t *testing.T, std **os.File, fn func()) string {
	t.Helper()
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	old := *std
	*std = w
	done := make(chan string)
	go func() {
		b, _ := io.ReadAll(r)
		done <- string(b)
	}()
	defer func() { *std = old }()
	fn()
	w.Close()
	return <-done
}

// menuLogged reports whether the fake UI logged a line that starts with prefix.
func menuLogged(u *fakeUI, prefix string) bool {
	return slices.ContainsFunc(u.log, func(l string) bool { return strings.HasPrefix(l, prefix) })
}

// menuCount counts the fake UI's lines that start with prefix.
func menuCount(u *fakeUI, prefix string) int {
	n := 0
	for _, l := range u.log {
		if strings.HasPrefix(l, prefix) {
			n++
		}
	}
	return n
}

func menuSave(t *testing.T, s *Setup, name, value string) {
	t.Helper()
	if err := s.SaveState(name, value); err != nil {
		t.Fatal(err)
	}
}

func menuGit(t *testing.T, args ...string) {
	t.Helper()
	if out, err := exec.Command("git", args...).CombinedOutput(); err != nil {
		t.Fatalf("git %q: %v\n%s", args, err, out)
	}
}

// Each menu item calls its action, and the menu opens again until Quit.
func TestMainMenuItems(t *testing.T) {
	for _, tc := range []struct {
		item    string
		answers []string // answers to the action's own questions
		want    string   // a line that only this action logs
	}{
		{"Paste config", []string{cancel}, "write: Paste your settings or shell code."},
		{"Edit config", nil, "note: Dry run: you are editing a copy of your config."},
		{"Link shell config", nil, "note:   would copy shell/"},
		{"Set up zsh + oh-my-zsh", nil, "note:   would install oh-my-zsh"},
		{"Configure git", nil, "note:   would ask for your git user.name"},
		{"Set up SSH key", nil, "note:   would create the SSH key"},
		{"Install packages", nil, "note:   would install "},
		{"Run installers", nil, "note:   would run 1 installer scripts"},
		{"Move dotfiles to XDG dirs", nil, "note:   would download xdg-ninja's notes"},
		{"Preview everything", nil, "heading: What Run everything would do for home. Nothing changes:"},
		{"Run everything", nil, "heading: Dry run: what Run everything would do for home:"},
		{"Check status", nil, ""},
		{"Uninstall", []string{"no"}, "confirm: Remove envsetup from this machine?"},
	} {
		t.Run(tc.item, func(t *testing.T) {
			s, u, _ := menuSetup(t, "home", "full")
			menuSave(t, s, "profile", "home")
			s.DryRun = true
			u.answer(tc.item)
			u.answer(tc.answers...)
			u.answer("Quit")
			out := menuCapture(t, &os.Stdout, s.MainMenu)
			if tc.want != "" && !menuLogged(u, tc.want) {
				t.Errorf("no %q in:\n%s", tc.want, strings.Join(u.log, "\n"))
			}
			if tc.item == "Check status" && !strings.Contains(out, "ok       profile: home\n") {
				t.Errorf("Check status printed:\n%s", out)
			}
			if got := menuCount(u, "choose: "); got != 2 {
				t.Errorf("the menu opened %d times, want 2 (the item, then Quit)", got)
			}
			if menuLogged(u, "fail: ") || menuLogged(u, "welcome: ") {
				t.Errorf("a failure or the welcome:\n%s", strings.Join(u.log, "\n"))
			}
		})
	}
}

// Without a profile, the menu shows the welcome, and the actions that need a profile fail.
func TestMainMenuNeedsProfile(t *testing.T) {
	s, u, f := menuSetup(t, "", "")
	items := []string{"Install packages", "Run installers", "Preview everything", "Run everything"}
	u.answer(items...)
	u.answer("Quit")
	s.MainMenu()
	if got := menuCount(u, "fail: Select a profile first."); got != len(items) {
		t.Errorf("%d failures, want %d:\n%s", got, len(items), strings.Join(u.log, "\n"))
	}
	if menuCount(u, "welcome: Welcome to envsetup.") != 1 {
		t.Errorf("no welcome, or more than one:\n%s", strings.Join(u.log, "\n"))
	}
	if slices.ContainsFunc(f.calls(), func(c string) bool { return strings.HasPrefix(c, "apt-get ") }) {
		t.Errorf("an action ran without a profile: %q", f.calls())
	}
}

// Esc ends the menu, and so does a real uninstall.
func TestMainMenuEnds(t *testing.T) {
	s, u, _ := menuSetup(t, "home", "full")
	u.answer(cancel)
	s.MainMenu()

	u.answer("Uninstall", "yes")
	s.MainMenu() // no Quit is left, so the menu must end by itself
	if !menuLogged(u, "plain: Left in place:") {
		t.Errorf("Uninstall did not run:\n%s", strings.Join(u.log, "\n"))
	}
}

// A work profile shows its mode, and a failed step leaves the menu open.
func TestMainMenuFailedStep(t *testing.T) {
	s, u, _ := menuSetup(t, "work", "lite")
	menuSave(t, s, "profile", "work")
	menuSave(t, s, "mode", "lite")
	t.Setenv("EDITOR", "false")
	u.answer("Edit config", "Quit")
	s.MainMenu()
	if s.Cfg.Mode != "lite" || menuCount(u, "fail: That step didn't finish.") != 1 || menuCount(u, "choose: ") != 2 {
		t.Errorf("mode %q:\n%s", s.Cfg.Mode, strings.Join(u.log, "\n"))
	}
}

// Preview everything is a dry run, also in a normal session, and the session stays normal after it.
func TestPreviewEverythingWritesNothing(t *testing.T) {
	s, u, f := menuSetup(t, "home", "full")
	menuSave(t, s, "profile", "home")
	before := snapshotHome(t)
	u.answer("Preview everything", "Quit")
	s.MainMenu()
	if d := diffSnapshots(before, snapshotHome(t)); len(d) > 0 {
		t.Errorf("Preview everything changed HOME: %q", d)
	}
	if s.DryRun {
		t.Error("the session is still a dry run")
	}
	for _, step := range []string{"note:   would copy shell/", "note:   would write ", "note:   would install ", "note:   would run ", "note:   would create the SSH key"} {
		if !menuLogged(u, step) {
			t.Errorf("no %q in:\n%s", step, strings.Join(u.log, "\n"))
		}
	}
	for _, c := range f.calls() {
		if !strings.HasPrefix(c, "git config ") && !strings.HasPrefix(c, "git -C ") {
			t.Errorf("the preview ran %q", c)
		}
	}
}

// A dry run of Run everything also runs Move dotfiles to XDG dirs when ENVSETUP_XDG_NINJA=1.
func TestRunEverythingDryRun(t *testing.T) {
	s, u, _ := menuSetup(t, "home", "full")
	before := snapshotHome(t)
	s.DryRun = true
	s.Cfg.XDGNinja = "1"
	s.RunEverything()
	if d := diffSnapshots(before, snapshotHome(t)); len(d) > 0 {
		t.Errorf("the dry run changed HOME: %q", d)
	}
	if !menuLogged(u, "note:   would download xdg-ninja's notes") {
		t.Errorf("no XDG step:\n%s", strings.Join(u.log, "\n"))
	}
}

func TestRunStep(t *testing.T) {
	s, u, _ := menuSetup(t, "home", "full")
	exitErr := exec.Command("false").Run()
	for _, tc := range []struct {
		name   string
		err    error
		failed bool
		stderr string
	}{
		{"no error", nil, false, ""},
		{"ErrFailed", ErrFailed, true, ""},
		{"a failed command", exitErr, true, ""},
		{"config.sh ran exit", &ExitError{Code: 3}, true, ""},
		{"a plain error", errors.New("mkdir: no room"), true, "mkdir: no room\n"},
		{"a wrapped ErrFailed", fmt.Errorf("step: %w", ErrFailed), true, ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			u.log = nil
			s.asked = "left over"
			stderr := menuCapture(t, &os.Stderr, func() { s.RunStep(func() error { return tc.err }) })
			want := 0
			if tc.failed {
				want = 1
			}
			if got := menuCount(u, "fail: That step didn't finish."); got != want || len(u.log) != want {
				t.Errorf("log = %q, want %d failure line", u.log, want)
			}
			if stderr != tc.stderr {
				t.Errorf("stderr = %q, want %q", stderr, tc.stderr)
			}
			if s.asked != "" {
				t.Error("RunStep kept the last step's state")
			}
		})
	}
}

func TestPickProfile(t *testing.T) {
	s, u, _ := menuSetup(t, "", "")
	for _, tc := range []struct {
		answers       []string
		profile, mode string
	}{
		{[]string{"work", "lite"}, "work", "lite"},
		{[]string{"home"}, "home", ""},
		{[]string{cancel}, "home", ""},             // a cancel saves nothing
		{[]string{"work", cancel}, "home", ""},     // also at the mode
		{[]string{"work", "full"}, "work", "full"}, // the mode comes back
	} {
		u.answer(tc.answers...)
		if err := s.PickProfile(); err != nil {
			t.Fatal(err)
		}
		if p, m := s.ReadState("profile", ""), s.ReadState("mode", ""); p != tc.profile || m != tc.mode {
			t.Errorf("after %q: profile %q, mode %q; want %q, %q", tc.answers, p, m, tc.profile, tc.mode)
		}
	}
}

// The labels count what the resolved config holds, so a change in config.sh changes them.
func TestProfileLabels(t *testing.T) {
	s, _, _ := menuSetup(t, "", "")
	label := func(p string) string { return s.profileLabel(p).Desc }
	home, err := s.Load("home", "full", s.UserConfig, true)
	if err != nil {
		t.Fatal(err)
	}
	n := len(home.ResolvedPackages)
	if want := fmt.Sprintf("bash · %d packages · 1 installer (docker)", n); label("home") != want {
		t.Errorf("home = %q, want %q", label("home"), want)
	}
	work, err := s.Load("work", "full", s.UserConfig, true)
	if err != nil {
		t.Fatal(err)
	}
	names := strings.Join(installerNames(work.ResolvedInstallers), ", ")
	if want := fmt.Sprintf("%d installers (%s)", len(work.ResolvedInstallers), names); !strings.HasSuffix(label("work"), want) || len(work.ResolvedInstallers) < 2 {
		t.Errorf("work = %q, want the suffix %q", label("work"), want)
	}
	want := fmt.Sprintf("uses sudo: installs %d packages and runs %d installers", len(work.ResolvedPackages), len(work.ResolvedInstallers))
	if got := s.modeLabels(); got[0].Value != "full" || got[0].Desc != want || got[1].Value != "lite" {
		t.Errorf("modeLabels = %+v, want %q first", got, want)
	}

	cfgFile := s.UserConfig
	if err := os.MkdirAll(filepath.Dir(cfgFile), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(cfgFile, []byte("ENVSETUP_SHELL=zsh\nENVSETUP_PACKAGES+=(smoke-extra)\nENVSETUP_SKIP=(docker)\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if want := fmt.Sprintf("zsh + oh-my-zsh · %d packages · no installers", n+1); label("home") != want {
		t.Errorf("home with config.sh = %q, want %q", label("home"), want)
	}

	// A config.sh that runs exit gives a label without a summary.
	if err := os.WriteFile(cfgFile, []byte("exit 3\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if got := s.profileLabel("home"); got.Value != "home" || got.Desc != "" {
		t.Errorf("profileLabel with exit = %+v", got)
	}
}

// statusReady makes every part that Status checks ok, for the home profile.
// newestRelease finds v1.2.3 in a local repo.
func statusReady(t *testing.T, s *Setup, f *fakes) {
	t.Helper()
	repo := t.TempDir()
	menuGit(t, "init", "-q", repo)
	menuGit(t, "-C", repo, "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "--allow-empty", "-m", "init")
	menuGit(t, "-C", repo, "tag", "v1.2.3")
	t.Setenv("ENVSETUP_REPO_URL", repo)
	s.Cfg.RepoURL = repo
	write := func(file, text string) {
		t.Helper()
		if err := os.MkdirAll(filepath.Dir(file), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(file, []byte(text), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	write(s.Data+"/version", "v1.0.0\n")
	write(s.Home+"/.bashrc", RCBegin+"\n# block\n"+RCEnd+"\n")
	write(s.UserConfig, "ENVSETUP_SHELL=bash\n")
	menuSave(t, s, "profile", "home")
	menuGit(t, "config", "--global", "--add", "include.path", s.GitFile)
	f.set("docker", fakeCmd{})
}

// menuStatus runs Status and returns the count of missing lines and its output.
func menuStatus(t *testing.T, s *Setup) (int, string) {
	t.Helper()
	var missing int
	var err error
	out := menuCapture(t, &os.Stdout, func() { missing, err = s.Status() })
	if err != nil {
		t.Fatalf("Status: %v", err)
	}
	return missing, out
}

func TestStatusOK(t *testing.T) {
	s, _, f := menuSetup(t, "home", "full")
	statusReady(t, s, f)
	missing, out := menuStatus(t, s)
	lines := strings.Split(strings.TrimSuffix(out, "\n"), "\n")
	want := []string{
		"ok       new shells use v1.0.0 (newest release: v1.2.3)",
		"ok       profile: home",
		"ok       " + s.Home + "/.bashrc has the envsetup block",
		"ok       " + s.Home + "/.gitconfig includes " + s.GitFile,
		fmt.Sprintf("ok       all %d packages are installed", len(s.Cfg.ResolvedPackages)),
		"ok       no tool from 1 installers is missing",
		"ok       " + s.UserConfig + " loads without errors",
	}
	if missing != 0 || !slices.Equal(lines, want) {
		t.Errorf("Status = %d missing:\n%s\nwant:\n%s", missing, out, strings.Join(want, "\n"))
	}
}

// Each missing part gives one missing line, and the rest stays ok.
func TestStatusMissing(t *testing.T) {
	for _, tc := range []struct {
		name   string
		break_ func(t *testing.T, s *Setup, f *fakes)
		want   string
	}{
		{"no copy of shell/", func(t *testing.T, s *Setup, f *fakes) { os.RemoveAll(s.Data) },
			"missing  no copy of shell/ in "},
		{"no profile", func(t *testing.T, s *Setup, f *fakes) { menuSave(t, s, "profile", "") },
			"missing  no saved profile. Select a profile in the menu"},
		{"no block", func(t *testing.T, s *Setup, f *fakes) { os.WriteFile(s.Home+"/.bashrc", nil, 0o644) },
			"has no envsetup block. Select Link shell config"},
		{"no block in .zshrc for a zsh user", func(t *testing.T, s *Setup, f *fakes) { t.Setenv("SHELL", "/usr/bin/zsh") },
			"missing  " + "HOME/.zshrc has no envsetup block. Select Link shell config"},
		{"no git include", func(t *testing.T, s *Setup, f *fakes) { os.Remove(s.Home + "/.gitconfig") },
			"does not include "},
		{"a package not installed", func(t *testing.T, s *Setup, f *fakes) { f.set("dpkg-query", fakeCmd{Code: 1}) },
			"missing  package git is not installed. Select Install packages"},
		{"no package manager", func(t *testing.T, s *Setup, f *fakes) { f.remove("apt-get") },
			"missing  no supported package manager, so envsetup cannot check "},
		{"a tool not on PATH", func(t *testing.T, s *Setup, f *fakes) { f.remove("docker") },
			"missing  docker is not on PATH. Select Run installers"},
		{"a failed command in config.sh", func(t *testing.T, s *Setup, f *fakes) {
			os.WriteFile(s.UserConfig, []byte("false\n"), 0o644)
		}, "missing  "},
	} {
		t.Run(tc.name, func(t *testing.T) {
			s, _, f := menuSetup(t, "home", "full")
			statusReady(t, s, f)
			tc.break_(t, s, f)
			missing, out := menuStatus(t, s)
			want := strings.ReplaceAll(tc.want, "HOME", s.Home)
			if !strings.Contains(out, want) {
				t.Errorf("no %q in:\n%s", want, out)
			}
			if got := strings.Count(out, "\nmissing ") + boolInt(strings.HasPrefix(out, "missing ")); got != missing || missing < 1 {
				t.Errorf("Status = %d missing, but printed %d:\n%s", missing, got, out)
			}
			if tc.name != "a package not installed" && missing != 1 {
				t.Errorf("Status = %d missing, want 1:\n%s", missing, out)
			}
		})
	}
}

func boolInt(b bool) int {
	if b {
		return 1
	}
	return 0
}

// A pinned tool that envsetup installed at another version is missing.
// Work lite checks no packages and no installers.
func TestStatusWork(t *testing.T) {
	s, _, f := menuSetup(t, "work", "full")
	statusReady(t, s, f)
	menuSave(t, s, "profile", "work")
	for _, tool := range []string{"aws", "helm", "kubectl", "terraform"} {
		f.set(tool, fakeCmd{})
	}
	if err := os.MkdirAll(filepath.Dir(s.Installed), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(s.Installed, []byte("kubectl 0.0.1\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	pin, err := s.Pin("kubectl")
	if err != nil || pin == "" {
		t.Fatalf("no pin for kubectl: %v", err)
	}
	missing, out := menuStatus(t, s)
	if want := "missing  kubectl 0.0.1 differs from the pin " + pin + ". Select Run installers"; missing != 1 || !strings.Contains(out, want) {
		t.Errorf("Status = %d missing, want 1 with %q:\n%s", missing, want, out)
	}
	if !strings.Contains(out, "ok       profile: work (full)") {
		t.Errorf("no work profile line:\n%s", out)
	}

	menuSave(t, s, "mode", "lite")
	missing, out = menuStatus(t, s)
	if missing != 0 || strings.Contains(out, "package") || strings.Contains(out, "installers") || !strings.Contains(out, "profile: work (lite)") {
		t.Errorf("work lite: %d missing:\n%s", missing, out)
	}
}

// Without config.sh, Status says that envsetup uses its defaults.
// A config.sh that runs exit returns an error.
func TestStatusConfig(t *testing.T) {
	s, _, f := menuSetup(t, "home", "full")
	statusReady(t, s, f)
	os.Remove(s.UserConfig)
	if _, out := menuStatus(t, s); !strings.Contains(out, "ok       no "+s.UserConfig+", so envsetup uses its defaults") {
		t.Errorf("no defaults line:\n%s", out)
	}
	if err := os.WriteFile(s.UserConfig, []byte("exit 4\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	var err error
	menuCapture(t, &os.Stdout, func() { _, err = s.Status() })
	if exitOf(err) != 4 {
		t.Errorf("Status with exit 4: %v", err)
	}
}

func TestNewestRelease(t *testing.T) {
	s, _, f := menuSetup(t, "home", "full")
	// Out of reach: the repo folder is not there.
	if got := s.newestRelease(); got != "" {
		t.Errorf("newestRelease of a missing repo = %q", got)
	}
	if _, out := menuStatus(t, s); !strings.Contains(out, "(newest release: unknown, GitHub is out of reach)") {
		t.Errorf("no unknown release in:\n%s", out)
	}

	// Without a URL, it asks GitHub, here through a fake git.
	s.Cfg = nil
	t.Setenv("ENVSETUP_REPO_URL", "")
	f.set("git", fakeCmd{Out: "a\trefs/tags/v1.9.0\na\trefs/tags/v1.10.0\n"})
	cfgCalls := len(f.calls())
	if got := s.newestRelease(); got != "v1.10.0" {
		t.Errorf("newestRelease = %q, want v1.10.0", got)
	}
	want := "git ls-remote --tags --refs https://github.com/hunterdw0007/envsetup.git v*"
	if c := f.calls()[cfgCalls:]; len(c) != 1 || c[0] != want {
		t.Errorf("calls = %q, want %q", c, want)
	}
}

// setup.sh --status returns 0 when every part is ok, and 1 when a part is missing.
// A config.sh that runs exit gives its exit code.
func TestMainStatus(t *testing.T) {
	s, _, f := menuSetup(t, "home", "full")
	statusReady(t, s, f)
	run := func() int {
		var code int
		menuCapture(t, &os.Stdout, func() { code = Main([]string{"--status"}, "v0.0.0-test") })
		return code
	}
	if code := run(); code != 0 {
		t.Errorf("--status with every part ok = %d, want 0", code)
	}
	f.remove("docker")
	if code := run(); code != 1 {
		t.Errorf("--status with a missing part = %d, want 1", code)
	}
	if err := os.WriteFile(s.UserConfig, []byte("exit 5\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if code := run(); code != 5 {
		t.Errorf("--status with exit 5 in config.sh = %d, want 5", code)
	}
}
