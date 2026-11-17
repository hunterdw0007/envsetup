package setup

import (
	"os"
	"path/filepath"
	"slices"
	"testing"
	"time"
)

// sandbox gives a test its own HOME and no XDG or ENVSETUP variables.
// So no test can reach the real ~/.config/envsetup.
func sandbox(t *testing.T) string {
	t.Helper()
	home := t.TempDir()
	t.Setenv("HOME", home)
	for _, v := range []string{"XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME",
		"ENVSETUP_STATE", "ENVSETUP_STATE_HOME", "ENVSETUP_ROOT", "SMOKE_CHOICES"} {
		t.Setenv(v, "")
		os.Unsetenv(v)
	}
	root, err := filepath.Abs("../..")
	if err != nil {
		t.Fatal(err)
	}
	t.Setenv("ENVSETUP_FILES", root)
	return home
}

func TestRemoveRCBlock(t *testing.T) {
	tests := []struct{ name, in, repl, want string }{
		{"no block", "a\nb\n", "", "a\nb\n"},
		{"one block", "a\n" + RCBegin + "\nx\n" + RCEnd + "\nb\n", "", "a\nb\n"},
		{"replacement", "a\n" + RCBegin + "\nx\n" + RCEnd + "\n", "NEW\n", "a\nNEW\n"},
		{"two blocks", RCBegin + "\n" + RCEnd + "\nm\n" + RCBegin + "\n" + RCEnd + "\n", "", "m\n"},
		{"begin without end stays", "a\n" + RCBegin + "\nx\n", "", "a\n" + RCBegin + "\nx\n"},
		{"second begin drops the held lines, like awk", RCBegin + "\nx\n" + RCBegin + "\ny\n", "", RCBegin + "\ny\n"},
		{"last line without newline", "a\nb", "", "a\nb\n"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			f := filepath.Join(t.TempDir(), "rc")
			if err := os.WriteFile(f, []byte(tt.in), 0o600); err != nil {
				t.Fatal(err)
			}
			if err := RemoveRCBlock(f, tt.repl); err != nil {
				t.Fatal(err)
			}
			got, _ := os.ReadFile(f)
			if string(got) != tt.want {
				t.Errorf("got %q, want %q", got, tt.want)
			}
			if fi, _ := os.Stat(f); fi.Mode().Perm() != 0o600 {
				t.Errorf("mode changed to %v", fi.Mode().Perm())
			}
		})
	}
}

func TestEnvDiff(t *testing.T) {
	got := envDiff([]string{"A=1", "B=2", "C=3", "_=x"}, []string{"A=1", "B=9", "D=4", "_=y"})
	slices.Sort(got)
	want := []string{"B=9", "C", "D=4", "_=y"}
	if !slices.Equal(got, want) {
		t.Errorf("got %q, want %q", got, want)
	}
}

func TestPaths(t *testing.T) {
	home := sandbox(t)
	var s Setup
	s.paths()
	if s.State != home+"/.config/envsetup" || s.Data != home+"/.local/share/envsetup" ||
		s.Installed != home+"/.local/state/envsetup/installed" {
		t.Errorf("defaults: %+v", s)
	}
	// A relative XDG value does not count.
	t.Setenv("XDG_CONFIG_HOME", "rel")
	t.Setenv("XDG_DATA_HOME", "/data")
	s.paths()
	if s.State != home+"/.config/envsetup" || s.Data != "/data/envsetup" {
		t.Errorf("XDG: state %q data %q", s.State, s.Data)
	}
	// An existing ~/.config/envsetup stays in use when the XDG folder has none.
	t.Setenv("XDG_CONFIG_HOME", home+"/xdg")
	s.paths()
	if s.State != home+"/xdg/envsetup" {
		t.Errorf("new XDG folder: %q", s.State)
	}
	os.MkdirAll(home+"/.config/envsetup", 0o755)
	s.paths()
	if s.State != home+"/.config/envsetup" {
		t.Errorf("old folder kept: %q", s.State)
	}
	// The block's ENVSETUP_STATE counts only for the same HOME.
	t.Setenv("ENVSETUP_STATE", "/elsewhere")
	t.Setenv("ENVSETUP_STATE_HOME", "/other-home")
	s.paths()
	if s.State != home+"/.config/envsetup" {
		t.Errorf("ENVSETUP_STATE of another HOME: %q", s.State)
	}
	t.Setenv("ENVSETUP_STATE_HOME", home)
	s.paths()
	if s.State != "/elsewhere" {
		t.Errorf("ENVSETUP_STATE: %q", s.State)
	}
}

func TestLoad(t *testing.T) {
	home := sandbox(t)
	s := &Setup{}
	s.paths()
	root, _ := s.root()
	s.Root = root
	cfg, err := s.Load("work", "full", s.UserConfig, true)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Shell != "bash" || cfg.XDGNinja != "0" || len(cfg.ResolvedPackages) == 0 || len(cfg.ResolvedInstallers) == 0 {
		t.Fatalf("defaults: %+v", cfg)
	}
	os.MkdirAll(s.State, 0o755)
	write := func(text string) {
		if err := os.WriteFile(s.UserConfig, []byte(text), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	write("ENVSETUP_SHELL=zsh\nENVSETUP_SKIP=(kubectl)\nENVSETUP_EXTRAS=(nope)\nexport SMOKE_X=1\n")
	cfg, err = s.Load("work", "full", s.UserConfig, true)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Shell != "zsh" || slices.ContainsFunc(cfg.ResolvedInstallers, func(p string) bool { return filepath.Base(p) == "kubectl.sh" }) {
		t.Errorf("config.sh: %+v", cfg)
	}
	if cfg.InstallersErr != `ENVSETUP_EXTRAS: no installer for "nope" (see installers/extras/)` {
		t.Errorf("InstallersErr: %q", cfg.InstallersErr)
	}
	if !slices.Contains(cfg.env, "SMOKE_X=1") {
		t.Errorf("env: %q", cfg.env)
	}
	write("ENVSETUP_SHELL=zsh\nfi\n")
	if cfg, _ = s.Load("home", "full", s.UserConfig, true); cfg.Warning == "" {
		t.Error("no warning for a syntax error")
	}
	// A background job of config.sh must not hold up the menu (review finding).
	write("sleep 5 &\nENVSETUP_SHELL=zsh\n")
	start := time.Now()
	if cfg, err = s.Load("home", "full", s.UserConfig, true); err != nil || cfg.Shell != "zsh" {
		t.Errorf("background job: %v, %+v", err, cfg)
	}
	if d := time.Since(start); d > 3*time.Second {
		t.Errorf("Load waited %v for a background job of config.sh", d)
	}
	write("exit 0\n")
	if _, err = s.Load("home", "full", s.UserConfig, true); err == nil || exitOf(err) != 0 {
		t.Errorf("exit 0: %v", err)
	}
	write("exit 7\n")
	if _, err = s.Load("home", "full", s.UserConfig, true); exitOf(err) != 7 {
		t.Errorf("exit: %v", err)
	}
	_ = home
}

func TestMainOptions(t *testing.T) {
	sandbox(t)
	tests := []struct {
		args []string
		want int
	}{
		{[]string{"--help"}, 0},
		{[]string{"--version"}, 0},
		{[]string{"--bogus"}, 2},
		{[]string{"--config"}, 2},
		{[]string{"--config", "/nonexistent"}, 2},
		{[]string{"--config", "main.go", "--config", "main.go"}, 2},
		{[]string{"--config", "main.go", "--uninstall"}, 2},
		{[]string{"--edit-config", "--uninstall"}, 2},
	}
	for _, tt := range tests {
		if got := Main(tt.args, "v0.0.0-test"); got != tt.want {
			t.Errorf("Main(%q) = %d, want %d", tt.args, got, tt.want)
		}
	}
}
