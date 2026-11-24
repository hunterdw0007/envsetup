package setup

import (
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
	"testing"
	"time"
)

// This file tests Main and the code around it: exit codes, root and version.

func TestExitCode(t *testing.T) {
	sigterm := exec.Command("sh", "-c", "kill -TERM $$").Run()
	tests := []struct {
		name       string
		err        error
		exit, step int
	}{
		{"normal exit", nil, 0, 1},
		{"exit code", exec.Command("sh", "-c", "exit 3").Run(), 3, 3},
		{"signal", sigterm, 128 + int(syscall.SIGTERM), 128 + int(syscall.SIGTERM)},
		{"plain error", errors.New("boom"), 1, 1},
		{"config.sh exit", &ExitError{5}, 1, 5},
	}
	for _, tt := range tests {
		if got := exitCode(tt.err); got != tt.exit {
			t.Errorf("%s: exitCode = %d, want %d", tt.name, got, tt.exit)
		}
		if tt.err == nil {
			continue // stepCode only gets a failure
		}
		if got := stepCode(tt.err); got != tt.step {
			t.Errorf("%s: stepCode = %d, want %d", tt.name, got, tt.step)
		}
	}
}

func TestExit(t *testing.T) {
	dir := t.TempDir() + "/tmp.x"
	if err := os.Mkdir(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	addCleanup(dir)
	code := -1
	osExit = func(c int) { code = c }
	t.Cleanup(func() { osExit = os.Exit })
	(&Setup{}).Exit(4)
	if code != 4 {
		t.Errorf("Exit(4) ended with %d", code)
	}
	if _, err := os.Stat(dir); !os.IsNotExist(err) {
		t.Errorf("Exit left the temporary folder %s", dir)
	}
}

func TestRoot(t *testing.T) {
	sandbox(t)
	t.Setenv("ENVSETUP_FILES", ".")
	want, _ := filepath.Abs(".")
	if got, err := (&Setup{}).root(); got != want || err != nil {
		t.Errorf("root with ENVSETUP_FILES = %q, %v; want %q", got, err, want)
	}
	// The test binary is in a folder without lib/common.sh.
	os.Unsetenv("ENVSETUP_FILES")
	if got, err := (&Setup{}).root(); got != "" || err == nil {
		t.Errorf("root with neither = %q, %v; want an error", got, err)
	}
}

func TestRootAboveBinary(t *testing.T) {
	sandbox(t)
	os.Unsetenv("ENVSETUP_FILES")
	dir := t.TempDir()
	if err := os.Mkdir(dir+"/lib", 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(dir+"/lib/common.sh", nil, 0o644); err != nil {
		t.Fatal(err)
	}
	executable = func() (string, error) { return dir + "/bin/envsetup", nil }
	t.Cleanup(func() { executable = os.Executable })
	if got, err := (&Setup{}).root(); got != dir || err != nil {
		t.Errorf("root = %q, %v; want %q", got, err, dir)
	}
}

func TestVersion(t *testing.T) {
	sandbox(t)
	f := fakeCommands(t)
	s := &Setup{Root: "/clone"}
	s.paths()

	f.set("git", fakeCmd{Out: "v1.2.0-3-gabc1234\n"})
	if got := s.version("v9.9.9"); got != "v1.2.0-3-gabc1234" {
		t.Errorf("a clone with tags: version = %q", got)
	}
	want := "git -C /clone describe --tags --match v[0-9]* --always --dirty"
	if c := f.calls(); len(c) != 1 || c[0] != want {
		t.Errorf("calls = %q, want %q", c, want)
	}

	f.set("git", fakeCmd{Code: 128}) // not a clone
	if got := s.version("v9.9.9"); got != "v9.9.9" {
		t.Errorf("a built version: version = %q, want v9.9.9", got)
	}
	if got := s.version(""); got != "unknown" {
		t.Errorf("nothing recorded: version = %q, want unknown", got)
	}
	if err := os.MkdirAll(s.Data, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(s.Data+"/version", []byte("v1.0.1\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if got := s.version(""); got != "v1.0.1" {
		t.Errorf("the recorded release: version = %q, want v1.0.1", got)
	}
}

// scriptUI makes Main answer from these lists, like the smoke test (internal/ui/script.go).
// It returns the path of the log of each question.
func scriptUI(t *testing.T, choices, confirms []string) string {
	t.Helper()
	dir := t.TempDir()
	write := func(name string, lines []string) string {
		p := filepath.Join(dir, name)
		text := strings.Join(lines, "\n")
		if len(lines) > 0 {
			text += "\n"
		}
		if err := os.WriteFile(p, []byte(text), 0o644); err != nil {
			t.Fatal(err)
		}
		return p
	}
	t.Setenv("SMOKE_CHOICES", write("choices", choices))
	t.Setenv("SMOKE_CONFIRMS", write("confirms", confirms))
	t.Setenv("SMOKE_LOG", filepath.Join(dir, "log"))
	t.Cleanup(func() {
		for _, name := range []string{"choices", "confirms"} {
			if b, _ := os.ReadFile(filepath.Join(dir, name)); len(b) > 0 {
				t.Errorf("%s left: %q", name, b)
			}
		}
	})
	return filepath.Join(dir, "log")
}

// mainTest gives Main a sandbox, fake commands and a TMPDIR of its own.
// The returned check fails the test if Main left a temporary folder.
func mainTest(t *testing.T) (home string, f *fakes, tmpLeft func()) {
	t.Helper()
	home = sandbox(t)
	t.Setenv("SHELL", "/bin/bash")
	f = fakeCommands(t)
	// Main reads its version from the clone, and lib/config.sh reads git/gitconfig.
	f.passThrough("git")
	tmp := t.TempDir()
	t.Setenv("TMPDIR", tmp)
	return home, f, func() {
		t.Helper()
		if left, _ := filepath.Glob(tmp + "/tmp.*"); len(left) > 0 {
			t.Errorf("Main left %q", left)
		}
	}
}

func TestMainDryRun(t *testing.T) {
	home, _, tmpLeft := mainTest(t)
	scriptUI(t, []string{"Quit"}, nil)
	before := snapshotHome(t)
	if got := Main([]string{"--dry-run"}, ""); got != 0 {
		t.Errorf("Main(--dry-run) = %d, want 0", got)
	}
	if d := diffSnapshots(before, snapshotHome(t)); len(d) > 0 {
		t.Errorf("the dry run changed %s: %q", home, d)
	}
	tmpLeft()
}

func TestMainStatusOption(t *testing.T) {
	_, f, tmpLeft := mainTest(t)
	scriptUI(t, nil, nil)
	f.set("curl", fakeCmd{Code: 6}) // GitHub is out of reach
	// Nothing is set up, so --status reports missing parts.
	if got := Main([]string{"--status"}, ""); got != 1 {
		t.Errorf("Main(--status) = %d, want 1", got)
	}
	tmpLeft()
}

func TestMainUninstall(t *testing.T) {
	home, _, tmpLeft := mainTest(t)
	rc := home + "/.bashrc"
	if err := os.WriteFile(rc, []byte("mine\n"+RCBegin+"\nx\n"+RCEnd+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	// Remove envsetup? yes. Every later question about what you own: keep.
	scriptUI(t, nil, []string{"yes"})
	if got := Main([]string{"--uninstall"}, ""); got != 0 {
		t.Errorf("Main(--uninstall) = %d, want 0", got)
	}
	if b, _ := os.ReadFile(rc); string(b) != "mine\n" {
		t.Errorf(".bashrc = %q, want the block gone", b)
	}
	tmpLeft()

	// A cancelled uninstall is not an error.
	scriptUI(t, nil, []string{"no"})
	if got := Main([]string{"--uninstall"}, ""); got != 0 {
		t.Errorf("Main(--uninstall) cancelled = %d, want 0", got)
	}
}

func TestMainEditConfig(t *testing.T) {
	home, _, tmpLeft := mainTest(t)
	scriptUI(t, nil, nil)
	t.Setenv("EDITOR", "true")
	if got := Main([]string{"--edit-config"}, ""); got != 0 {
		t.Errorf("Main(--edit-config) = %d, want 0", got)
	}
	if !isFile(home + "/.config/envsetup/config.sh") {
		t.Error("--edit-config did not create config.sh")
	}
	// A failed editor ends envsetup with the editor's own code.
	editor := t.TempDir() + "/editor"
	if err := os.WriteFile(editor, []byte("#!/bin/sh\nexit 7\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("EDITOR", editor)
	if got := Main([]string{"--edit-config"}, ""); got != 7 {
		t.Errorf("Main(--edit-config) with a failed editor = %d, want 7", got)
	}
	tmpLeft()
}

func TestMainConfig(t *testing.T) {
	home, _, tmpLeft := mainTest(t)
	extra := t.TempDir() + "/extra.sh"
	if err := os.WriteFile(extra, []byte("ENVSETUP_SMOKE_EXTRA=1\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	scriptUI(t, []string{"Quit"}, nil)
	if got := Main([]string{"--config", extra}, ""); got != 0 {
		t.Errorf("Main(--config) = %d, want 0", got)
	}
	if b, _ := os.ReadFile(home + "/.config/envsetup/config.sh"); !strings.Contains(string(b), "ENVSETUP_SMOKE_EXTRA=1") {
		t.Errorf("config.sh = %q, want the text of --config", b)
	}
	tmpLeft()

	// A config.sh with a syntax error fails the step, and Main ends with 1.
	if err := os.WriteFile(extra, []byte("if\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	scriptUI(t, nil, nil)
	if got := Main([]string{"--config", extra}, ""); got != 1 {
		t.Errorf("Main(--config) with a broken file = %d, want 1", got)
	}
}

// TestMainLeaksNoHandler checks that Main stops its signal handler when it returns (#194).
func TestMainLeaksNoHandler(t *testing.T) {
	sandbox(t)
	// The first call starts os/signal's own goroutine, which stays.
	Main([]string{"--help"}, "")
	before := runtime.NumGoroutine()
	for range 5 {
		Main([]string{"--help"}, "")
	}
	// A stopped handler's goroutine ends soon after Main returns.
	deadline := time.Now().Add(2 * time.Second)
	for runtime.NumGoroutine() > before && time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
	}
	if n := runtime.NumGoroutine(); n > before {
		t.Errorf("%d goroutines after 5 calls to Main, %d before", n, before)
	}
}

// TestMainSIGINT runs Main in a child process, so the signal does not stop go test.
// The scripted menu sends SIGINT to its process group, as Ctrl-C does.
func TestMainSIGINT(t *testing.T) {
	if os.Getenv("ENVSETUP_TEST_SIGINT") != "" {
		os.Exit(Main([]string{"--dry-run"}, ""))
	}
	_, _, tmpLeft := mainTest(t)
	scriptUI(t, nil, nil)
	if err := os.WriteFile(os.Getenv("SMOKE_CHOICES"), []byte("SIGINT\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	exe, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	c := exec.Command(exe, "-test.run=^TestMainSIGINT$")
	c.Env = append(os.Environ(), "ENVSETUP_TEST_SIGINT=1")
	c.SysProcAttr = &syscall.SysProcAttr{Setpgid: true} // its own process group
	out, err := c.CombinedOutput()
	if got := exitCode(err); got != 130 {
		t.Errorf("Main after SIGINT ended with %d, want 130\n%s", got, out)
	}
	tmpLeft()
}
