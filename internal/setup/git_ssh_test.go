package setup

import (
	"os"
	"os/exec"
	"slices"
	"strconv"
	"strings"
	"testing"
)

// gitTest returns a Setup whose git runs for real on the sandbox's ~/.gitconfig.
func gitTest(t *testing.T, profile, mode string) (*Setup, *fakeUI, *fakes) {
	t.Helper()
	s, u, f := newTestSetup(t, profile, mode)
	f.realGit()
	t.Setenv("HOSTNAME", "box")
	return s, u, f
}

// gitConfig runs the real git without the call log and returns its output lines.
func gitConfig(t *testing.T, f *fakes, args ...string) []string {
	t.Helper()
	out, _ := exec.Command(f.cmds["git"].Real, append([]string{"config"}, args...)...).Output()
	return splitLines(strings.TrimRight(string(out), "\n"))
}

func TestConfigureGitDryRun(t *testing.T) {
	s, u, _ := gitTest(t, "home", "full")
	s.DryRun = true
	writeTestFile(t, s.Home+"/.gitconfig", "[core]\n\teditor = vi\n")
	before := snapshotHome(t)
	if err := s.ConfigureGit(); err != nil {
		t.Fatal(err)
	}
	n := len(s.Cfg.GitConfig)
	if n == 0 {
		t.Fatal("git/gitconfig has no settings")
	}
	checkUILog(t, u.log, []string{
		"note:   would write " + strconv.Itoa(n) + " git settings to " + s.GitFile + " and include it from ~/.gitconfig",
		"note:   would ask for your git user.name",
		"note:   would ask for your git user.email",
	})
	if d := diffSnapshots(before, snapshotHome(t)); len(d) > 0 {
		t.Errorf("the dry run changed HOME: %q", d)
	}
}

// TestConfigureGitRuns covers the first run, the second run, a dry run after them and Uninstall.
func TestConfigureGitRuns(t *testing.T) {
	s, u, f := gitTest(t, "home", "full")
	writeTestFile(t, s.Home+"/.gitconfig", "[core]\n\teditor = vi\n")
	u.answer("Me", "me@example.com")
	if err := s.ConfigureGit(); err != nil {
		t.Fatal(err)
	}
	if got := gitConfig(t, f, "--file", s.GitFile, "--list"); !slices.Equal(got, s.Cfg.GitConfig) {
		t.Errorf("%s holds %q, want %q", s.GitFile, got, s.Cfg.GitConfig)
	}
	if got := gitConfig(t, f, "--global", "--get-all", "include.path"); !slices.Equal(got, []string{s.GitFile}) {
		t.Errorf("include.path = %q", got)
	}
	if got := gitConfig(t, f, "--global", "user.name"); !slices.Equal(got, []string{"Me"}) {
		t.Errorf("user.name = %q", got)
	}
	if got := gitConfig(t, f, "--global", "user.email"); !slices.Equal(got, []string{"me@example.com"}) {
		t.Errorf("user.email = %q", got)
	}
	if !slices.Contains(u.log, "success: Included "+s.GitFile+" in $HOME/.gitconfig") {
		t.Errorf("UI log = %q", u.log)
	}
	first := snapshotHome(t)

	u.log = nil
	if err := s.ConfigureGit(); err != nil {
		t.Fatal(err)
	}
	checkUILog(t, u.log, []string{"success: Updated " + s.GitFile})
	if d := diffSnapshots(first, snapshotHome(t)); len(d) > 0 {
		t.Errorf("the second run changed %q", d)
	}

	u.log = nil
	s.DryRun = true
	if err := s.ConfigureGit(); err != nil {
		t.Fatal(err)
	}
	checkUILog(t, u.log, []string{"note:   would rewrite " + s.GitFile + " (" + strconv.Itoa(len(s.Cfg.GitConfig)) + " git settings)"})
	s.DryRun = false

	u.answer("yes")
	if err := s.Uninstall(); err != nil {
		t.Fatal(err)
	}
	if exists(s.GitFile) {
		t.Error("Uninstall left the generated file")
	}
	if got := gitConfig(t, f, "--global", "--get-all", "include.path"); len(got) > 0 {
		t.Errorf("Uninstall left include.path = %q", got)
	}
	// The identity and the user's own settings stay.
	for key, want := range map[string]string{"user.name": "Me", "user.email": "me@example.com", "core.editor": "vi"} {
		if got := gitConfig(t, f, "--global", key); !slices.Equal(got, []string{want}) {
			t.Errorf("after Uninstall, %s = %q, want %q", key, got, want)
		}
	}
}

// TestConfigureGitSkipsIdentity checks that no answer saves an empty name or a bad email (#49).
func TestConfigureGitSkipsIdentity(t *testing.T) {
	for _, tc := range []struct {
		name, nameAnswer, emailAnswer, emailWarn string
	}{
		{"empty", "  ", "", "warn: Skipped user.email. git needs it before your first commit: git config --global user.email ..."},
		{"cancelled", cancel, cancel, "warn: Skipped user.email. git needs it before your first commit: git config --global user.email ..."},
		{"not an email", "", "nope", `warn: Skipped user.email: "nope" is not an email address`},
	} {
		t.Run(tc.name, func(t *testing.T) {
			s, u, f := gitTest(t, "home", "full")
			u.answer(tc.nameAnswer, tc.emailAnswer)
			if err := s.ConfigureGit(); err != nil {
				t.Fatal(err)
			}
			want := []string{
				"success: Included " + s.GitFile + " in $HOME/.gitconfig",
				"input: ",
				"warn: Skipped user.name. git needs it before your first commit: git config --global user.name ...",
				"input: ",
				tc.emailWarn,
			}
			checkUILog(t, u.log, want)
			for _, key := range []string{"user.name", "user.email"} {
				if got := gitConfig(t, f, "--global", key); len(got) > 0 {
					t.Errorf("%s = %q, want unset", key, got)
				}
			}
		})
	}
}

// TestConfigureGitMergesConfig checks that ENVSETUP_GIT_CONFIG adds to git/gitconfig.
// A name from config.sh also means that envsetup does not ask for it.
func TestConfigureGitMergesConfig(t *testing.T) {
	s, u, f := gitTest(t, "home", "full")
	defaults := len(s.Cfg.GitConfig)
	writeTestFile(t, s.UserConfig, `ENVSETUP_GIT_CONFIG+=("user.name=From Config" "pull.rebase=false")`+"\n")
	cfg, err := s.Load("home", "full", s.UserConfig, true)
	if err != nil {
		t.Fatal(err)
	}
	s.Cfg = cfg
	if len(cfg.GitConfig) != defaults+2 {
		t.Fatalf("GitConfig has %d entries, want %d", len(cfg.GitConfig), defaults+2)
	}

	s.DryRun = true
	if err := s.ConfigureGit(); err != nil {
		t.Fatal(err)
	}
	if slices.Contains(u.log, "note:   would ask for your git user.name") || !slices.Contains(u.log, "note:   would ask for your git user.email") {
		t.Errorf("dry run log = %q", u.log)
	}
	s.DryRun = false

	u.log = nil
	u.answer("me@example.com")
	if err := s.ConfigureGit(); err != nil {
		t.Fatal(err)
	}
	got := gitConfig(t, f, "--file", s.GitFile, "--list")
	if !slices.Contains(got, "user.name=From Config") || !slices.Contains(got, "pull.rebase=false") || len(got) != defaults+2 {
		t.Errorf("%s holds %q", s.GitFile, got)
	}
	if got := gitConfig(t, f, "--global", "--includes", "user.name"); !slices.Equal(got, []string{"From Config"}) {
		t.Errorf("user.name with includes = %q", got)
	}
}

// TestConfigureGitLite checks that lite mode writes only ~/.gitconfig and envsetup's own files.
func TestConfigureGitLite(t *testing.T) {
	s, u, _ := gitTest(t, "work", "lite")
	before := snapshotHome(t)
	u.answer("Me", "me@example.com")
	if err := s.ConfigureGit(); err != nil {
		t.Fatal(err)
	}
	d := diffSnapshots(before, snapshotHome(t))
	if !slices.Contains(d, s.Home+"/.gitconfig") {
		t.Errorf("lite mode did not write ~/.gitconfig: %q", d)
	}
	for _, p := range d {
		if p != s.Home+"/.gitconfig" && !strings.HasPrefix(p, s.Home+"/.config") {
			t.Errorf("lite mode wrote %s", p)
		}
	}
}

// TestConfigureGitBadEntry checks that a bad entry keeps the last good file.
func TestConfigureGitBadEntry(t *testing.T) {
	s, u, f := gitTest(t, "home", "full")
	u.answer("Me", "me@example.com")
	if err := s.ConfigureGit(); err != nil {
		t.Fatal(err)
	}
	good := readTestFile(t, s.GitFile)
	s.Cfg.GitConfig = append(s.Cfg.GitConfig, "nosection=x")
	if err := s.ConfigureGit(); err == nil {
		t.Error("no error for a key without a section")
	}
	if got := readTestFile(t, s.GitFile); got != good {
		t.Errorf("a bad entry changed %s", s.GitFile)
	}
	if got := gitConfig(t, f, "--global", "user.name"); !slices.Equal(got, []string{"Me"}) {
		t.Errorf("user.name = %q", got)
	}
}

func TestConfigureGitErrors(t *testing.T) {
	t.Run("state folder is a file", func(t *testing.T) {
		s, _, _ := gitTest(t, "home", "full")
		writeTestFile(t, s.State, "")
		if err := s.ConfigureGit(); err == nil {
			t.Error("no error")
		}
	})
	t.Run("temporary file is a folder", func(t *testing.T) {
		s, _, _ := gitTest(t, "home", "full")
		if err := os.MkdirAll(s.GitFile+".tmp", 0o755); err != nil {
			t.Fatal(err)
		}
		if err := s.ConfigureGit(); err == nil {
			t.Error("no error")
		}
	})
	t.Run("generated file is a folder", func(t *testing.T) {
		s, _, _ := gitTest(t, "home", "full")
		writeTestFile(t, s.GitFile+"/x", "")
		if err := s.ConfigureGit(); err == nil {
			t.Error("no error")
		}
	})
	t.Run("entry without =", func(t *testing.T) {
		s, u, f := gitTest(t, "home", "full")
		s.Cfg.GitConfig = []string{"core.pager"}
		u.answer("", "")
		if err := s.ConfigureGit(); err != nil {
			t.Fatal(err)
		}
		// Like ${kv#*=}, the value is the whole entry.
		if got := gitConfig(t, f, "--file", s.GitFile, "core.pager"); !slices.Equal(got, []string{"core.pager"}) {
			t.Errorf("core.pager = %q", got)
		}
	})
	t.Run("failed include", func(t *testing.T) {
		s, _, f := gitTest(t, "home", "full")
		failingGit(t, f, "include.path "+s.GitFile, 4)
		if err := s.ConfigureGit(); exitCode(err) != 4 {
			t.Errorf("err = %v, want exit 4", err)
		}
	})
	t.Run("failed identity write", func(t *testing.T) {
		s, u, f := gitTest(t, "home", "full")
		u.answer("Me")
		failingGit(t, f, "user.name Me", 4)
		if err := s.ConfigureGit(); exitCode(err) != 4 {
			t.Errorf("err = %v, want exit 4", err)
		}
	})
}

func whoami(t *testing.T) string {
	t.Helper()
	out, err := exec.Command("id", "-un").Output()
	if err != nil {
		t.Fatal(err)
	}
	return strings.TrimSpace(string(out))
}

func TestSetUpSSHKeyDryRun(t *testing.T) {
	const url = "https://github.com/settings/keys"
	for _, tc := range []struct {
		name  string
		gh    bool
		signs bool
		want  []string
	}{
		{"gh", true, false, []string{
			"would ask to add it to your GitHub account with gh",
			"would ask to sign your git commits with it",
			"would add it to your GitHub account as a signing key with gh, if you say yes to both questions",
		}},
		{"no gh", false, false, []string{
			"would show the public key, to add at " + url,
			"would ask to sign your git commits with it",
			"would show where to add it as a signing key, if you say yes to signing: " + url,
		}},
		{"own signing settings", false, true, []string{
			"would show the public key, to add at " + url,
		}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			s, u, f := gitTest(t, "home", "full")
			s.DryRun = true
			if !tc.gh {
				f.remove("gh")
			}
			if tc.signs {
				writeTestFile(t, s.Home+"/.gitconfig", "[commit]\n\tgpgsign = true\n")
			}
			before := snapshotHome(t)
			if err := s.SetUpSSHKey(); err != nil {
				t.Fatal(err)
			}
			key := s.Home + "/.ssh/id_ed25519"
			want := []string{
				"note:   would create the SSH key " + key + " (" + whoami(t) + "@box)",
				"note:   would let ssh-keygen ask for a passphrase",
			}
			for _, w := range tc.want {
				want = append(want, "note:   "+w)
			}
			checkUILog(t, u.log, want)
			if d := diffSnapshots(before, snapshotHome(t)); len(d) > 0 {
				t.Errorf("the dry run changed HOME: %q", d)
			}
		})
	}
}

// TestSetUpSSHKeyRuns covers the first run with gh, the second run and Uninstall.
func TestSetUpSSHKeyRuns(t *testing.T) {
	s, u, f := gitTest(t, "home", "full")
	fakeKeygen(t, f)
	f.set("gh", fakeCmd{})
	key := s.Home + "/.ssh/id_ed25519"
	comment := whoami(t) + "@box"
	u.answer("yes", "yes")
	if err := s.SetUpSSHKey(); err != nil {
		t.Fatal(err)
	}
	want := []string{
		"ssh-keygen -t ed25519 -C " + comment + " -f " + key,
		"gh ssh-key add " + key + ".pub --title " + comment,
		"gh ssh-key add " + key + ".pub --type signing --title " + comment + " signing",
	}
	if c := slices.DeleteFunc(f.calls(), func(c string) bool { return strings.HasPrefix(c, "git ") }); !slices.Equal(c, want) {
		t.Errorf("calls = %q, want %q", c, want)
	}
	for k, v := range map[string]string{"gpg.format": "ssh", "user.signingkey": key + ".pub", "commit.gpgsign": "true"} {
		if got := gitConfig(t, f, "--global", k); !slices.Equal(got, []string{v}) {
			t.Errorf("%s = %q, want %q", k, got, v)
		}
	}
	if fi, err := os.Stat(s.Home + "/.ssh"); err != nil || fi.Mode().Perm() != 0o700 {
		t.Errorf("~/.ssh: %v, %v", fi, err)
	}
	if !isFile(s.SSHMarker) {
		t.Error("no marker for the key")
	}
	if !slices.Contains(u.log, "success: Added the key to your GitHub account as a signing key") {
		t.Errorf("UI log = %q", u.log)
	}
	first := snapshotHome(t)

	u.log = nil
	if err := s.SetUpSSHKey(); err != nil {
		t.Fatal(err)
	}
	checkUILog(t, u.log, []string{"warn: An SSH key already exists: " + key})
	if d := diffSnapshots(first, snapshotHome(t)); len(d) > 0 {
		t.Errorf("the second run changed %q", d)
	}

	// Uninstall removes the signing settings and, after a no, the key.
	u.answer("yes", "no")
	if err := s.Uninstall(); err != nil {
		t.Fatal(err)
	}
	for _, k := range []string{"gpg.format", "user.signingkey", "commit.gpgsign"} {
		if got := gitConfig(t, f, "--global", k); len(got) > 0 {
			t.Errorf("Uninstall left %s = %q", k, got)
		}
	}
	if exists(key) || exists(key+".pub") || exists(s.Home+"/.ssh") {
		t.Error("Uninstall left the key or ~/.ssh")
	}
}

func TestSetUpSSHKeyNoGH(t *testing.T) {
	s, u, f := gitTest(t, "home", "full")
	fakeKeygen(t, f)
	f.remove("gh")
	key := s.Home + "/.ssh/id_ed25519"
	u.answer("yes")
	if err := s.SetUpSSHKey(); err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{
		"plain: Add this public key at https://github.com/settings/keys:",
		"plain: ssh-ed25519 AAAA " + whoami(t) + "@box",
		`warn: Add the public key as a signing key at https://github.com/settings/keys (key type "Signing Key")`,
	} {
		if !slices.Contains(u.log, want) {
			t.Errorf("UI log = %q, want %q", u.log, want)
		}
	}
	if got := gitConfig(t, f, "--global", "user.signingkey"); !slices.Equal(got, []string{key + ".pub"}) {
		t.Errorf("user.signingkey = %q", got)
	}

	// A cancel keeps the key.
	// Uninstall still removes the signing settings.
	u.answer("yes", cancel)
	if err := s.Uninstall(); err != nil {
		t.Fatal(err)
	}
	if !isFile(key) || !isFile(key+".pub") {
		t.Error("Uninstall deleted the key on a cancel")
	}
	if got := gitConfig(t, f, "--global", "user.signingkey"); len(got) > 0 {
		t.Errorf("Uninstall left user.signingkey = %q", got)
	}
}

// TestSetUpSSHKeyGHFails checks that a failed gh shows the key instead.
func TestSetUpSSHKeyGHFails(t *testing.T) {
	s, u, f := gitTest(t, "home", "full")
	fakeKeygen(t, f)
	f.set("gh", fakeCmd{Code: 1})
	u.answer("yes", "no")
	if err := s.SetUpSSHKey(); err != nil {
		t.Fatal(err)
	}
	if !slices.Contains(u.log, "plain: Add this public key at https://github.com/settings/keys:") {
		t.Errorf("UI log = %q", u.log)
	}
	if got := gitConfig(t, f, "--global", "commit.gpgsign"); len(got) > 0 {
		t.Errorf("a no to signing set commit.gpgsign = %q", got)
	}
}

// TestSetUpSSHKeyUserOwned checks that a key and signing settings of the user's own stay in place.
func TestSetUpSSHKeyUserOwned(t *testing.T) {
	s, u, f := gitTest(t, "home", "full")
	fakeKeygen(t, f)
	f.remove("gh")
	writeTestFile(t, s.Home+"/.gitconfig", "[user]\n\tsigningkey = ABC\n")
	if err := s.SetUpSSHKey(); err != nil {
		t.Fatal(err)
	}
	if !slices.Contains(u.log, "warn: git already has signing settings, so envsetup leaves them as they are.") {
		t.Errorf("UI log = %q", u.log)
	}
	if got := gitConfig(t, f, "--global", "user.signingkey"); !slices.Equal(got, []string{"ABC"}) {
		t.Errorf("user.signingkey = %q, want ABC", got)
	}
}

// TestSetUpSSHKeyUserKey checks that a key the user made has no marker.
// So Uninstall asks nothing about it and keeps it.
// newTestSetup runs once in each test, so this is its own test.
func TestSetUpSSHKeyUserKey(t *testing.T) {
	s, u, f := gitTest(t, "home", "full")
	writeTestFile(t, s.Home+"/.ssh/id_ed25519", "mine\n")
	if err := s.SetUpSSHKey(); err != nil {
		t.Fatal(err)
	}
	u.answer("yes")
	if err := s.Uninstall(); err != nil {
		t.Fatal(err)
	}
	if got := readTestFile(t, s.Home+"/.ssh/id_ed25519"); got != "mine\n" {
		t.Errorf("the user's key = %q", got)
	}
	if c := slices.DeleteFunc(f.calls(), func(c string) bool { return strings.HasPrefix(c, "git ") }); len(c) > 0 {
		t.Errorf("calls = %q", c)
	}
}

func TestSetUpSSHKeyErrors(t *testing.T) {
	t.Run("no ssh-keygen", func(t *testing.T) {
		s, u, f := gitTest(t, "home", "full")
		f.remove("ssh-keygen")
		if err := s.SetUpSSHKey(); err != ErrFailed {
			t.Errorf("err = %v, want ErrFailed", err)
		}
		checkUILog(t, u.log, []string{"fail: This machine has no ssh-keygen. Install openssh-client. Then run Set up SSH key again."})
	})
	t.Run("ssh-keygen fails", func(t *testing.T) {
		s, _, f := gitTest(t, "home", "full")
		f.set("ssh-keygen", fakeCmd{Code: 1})
		if err := s.SetUpSSHKey(); exitCode(err) != 1 {
			t.Errorf("err = %v, want exit 1", err)
		}
		if exists(s.SSHMarker) {
			t.Error("a failed ssh-keygen wrote the marker")
		}
	})
	t.Run("no id", func(t *testing.T) {
		s, _, f := gitTest(t, "home", "full")
		f.set("id", fakeCmd{Code: 1})
		if err := s.SetUpSSHKey(); err == nil {
			t.Error("no error")
		}
	})
	t.Run("~/.ssh cannot be created", func(t *testing.T) {
		s, _, f := gitTest(t, "home", "full")
		fakeKeygen(t, f)
		if err := os.Chmod(s.Home, 0o555); err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { os.Chmod(s.Home, 0o755) })
		if os.Geteuid() != 0 && s.SetUpSSHKey() == nil {
			t.Error("no error")
		}
	})
	t.Run("marker folder is a file", func(t *testing.T) {
		s, _, f := gitTest(t, "home", "full")
		fakeKeygen(t, f)
		writeTestFile(t, s.State, "")
		if err := s.SetUpSSHKey(); err == nil {
			t.Error("no error")
		}
	})
	t.Run("failed signing setting", func(t *testing.T) {
		s, u, f := gitTest(t, "home", "full")
		fakeKeygen(t, f)
		f.remove("gh")
		u.answer("yes")
		failingGit(t, f, "gpg.format ssh", 4)
		if err := s.SetUpSSHKey(); exitCode(err) != 4 {
			t.Errorf("err = %v, want exit 4", err)
		}
	})
}

func TestHostname(t *testing.T) {
	t.Setenv("HOSTNAME", "box")
	if got := hostname(); got != "box" {
		t.Errorf("hostname() = %q, want box", got)
	}
	os.Unsetenv("HOSTNAME")
	want, err := os.Hostname()
	if err != nil || want == "" {
		t.Skip("no hostname")
	}
	if got := hostname(); got != want {
		t.Errorf("hostname() = %q, want %q", got, want)
	}
}
