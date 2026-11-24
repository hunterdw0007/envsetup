package setup

// This file holds shared helpers that run actions in go test.
// newTestSetup builds a Setup with a fake UI and fake commands.
// snapshotHome lists everything under HOME, so a test can prove that a dry run wrote nothing.

import (
	"encoding/json"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"syscall"
	"testing"

	"github.com/hunterdw0007/envsetup/internal/ui"
)

// TestMain runs the test binary as a fake command when a fake's link starts it.
// Otherwise it runs the tests.
func TestMain(m *testing.M) {
	if bin := os.Getenv("ENVSETUP_FAKE_BIN"); bin != "" {
		name := filepath.Base(os.Args[0])
		if _, err := os.Lstat(filepath.Join(bin, name)); err == nil {
			os.Exit(runFake(filepath.Dir(bin), name, os.Args[1:]))
		}
	}
	os.Exit(m.Run())
}

// runFake logs the call and answers with the output and exit code that the test set.
func runFake(dir, name string, args []string) int {
	f, err := os.OpenFile(filepath.Join(dir, "calls"), os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		fmt.Fprintln(os.Stderr, "fake:", err)
		return 127
	}
	// One JSON array for each call keeps an argument with a newline in one call.
	line, _ := json.Marshal(append([]string{name}, args...))
	fmt.Fprintf(f, "%s\n", line)
	f.Close()
	var cmds map[string]fakeCmd
	data, _ := os.ReadFile(filepath.Join(dir, "fakes.json"))
	_ = json.Unmarshal(data, &cmds)
	c, ok := cmds[name]
	if !ok {
		fmt.Fprintln(os.Stderr, "fake: the test did not expect", name)
		return 127
	}
	if c.Real != "" {
		err := syscall.Exec(c.Real, append([]string{name}, args...), os.Environ())
		fmt.Fprintln(os.Stderr, "fake:", err)
		return 127
	}
	fmt.Print(c.Out)
	return c.Code
}

// guarded lists the commands that reach the network, root or the system.
// Each one is a fake on PATH, and the real one is never on PATH.
// A call to a guarded command that the test did not set fails the test.
var guarded = []string{
	"apt-get", "apt", "dnf", "yum", "zypper", "pacman", "apk", "brew", "nix-env", "rpm",
	"dpkg", "snap", "flatpak", "docker",
	"sudo", "sudoedit", "doas", "pkexec", "su", "run0", "chsh",
	"curl", "wget", "git", "gh", "ssh-keygen", "ssh", "zsh", "gpg",
}

// fakeCmd is what a fake command prints to stdout and the exit code it returns.
// With Real set, the fake logs the call and then runs that program instead.
type fakeCmd struct {
	Out  string
	Code int
	Real string
}

// fakes holds the fake commands of one test.
type fakes struct {
	t    *testing.T
	dir  string // holds calls and fakes.json
	bin  string // the fakes, first on PATH
	real string // links to the real commands, except the guarded ones
	path string // PATH before the fakes
	cmds map[string]fakeCmd
}

// fakeCommands sets PATH to the fakes, then the real commands without the guarded ones.
// The test ends with an error if anything called a guarded command that the test did not set.
func fakeCommands(t *testing.T) *fakes {
	t.Helper()
	dir := t.TempDir()
	f := &fakes{t: t, dir: dir, bin: filepath.Join(dir, "bin"), real: filepath.Join(dir, "real"), path: os.Getenv("PATH"), cmds: map[string]fakeCmd{}}
	for _, d := range []string{f.bin, f.real} {
		if err := os.Mkdir(d, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	for _, d := range filepath.SplitList(os.Getenv("PATH")) {
		entries, _ := os.ReadDir(d)
		for _, e := range entries {
			if !slices.Contains(guarded, e.Name()) {
				// The first folder on PATH wins, so a later link of the same name fails, as it should.
				_ = os.Symlink(filepath.Join(d, e.Name()), filepath.Join(f.real, e.Name()))
			}
		}
	}
	for _, name := range guarded {
		f.link(name)
	}
	f.save()
	t.Setenv("ENVSETUP_FAKE_BIN", f.bin)
	t.Setenv("GORACE", "atexit_sleep_ms=0") // a race-built fake otherwise sleeps 1s when it exits
	t.Setenv("PATH", f.bin+":"+f.real)
	t.Cleanup(func() {
		if u := f.unexpected(); len(u) > 0 {
			t.Errorf("unexpected commands:\n%s", strings.Join(u, "\n"))
		}
	})
	return f
}

func (f *fakes) link(name string) {
	f.t.Helper()
	exe, err := os.Executable()
	if err != nil {
		f.t.Fatal(err)
	}
	if err := os.Symlink(exe, filepath.Join(f.bin, name)); err != nil && !os.IsExist(err) {
		f.t.Fatal(err)
	}
}

func (f *fakes) save() {
	f.t.Helper()
	data, err := json.Marshal(f.cmds)
	if err != nil {
		f.t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(f.dir, "fakes.json"), data, 0o644); err != nil {
		f.t.Fatal(err)
	}
}

// set makes name a fake that the test expects, with this output and exit code.
// name may be any command, also one that is not guarded.
func (f *fakes) set(name string, c fakeCmd) {
	f.t.Helper()
	f.cmds[name] = c
	f.link(name)
	f.save()
}

// passThrough makes name a fake that logs each call and runs the real command.
// Use it only for a call that stays on this machine, such as git config.
func (f *fakes) passThrough(name string) {
	f.t.Helper()
	for _, d := range filepath.SplitList(f.path) {
		p := filepath.Join(d, name)
		if fi, err := os.Stat(p); err == nil && fi.Mode().IsRegular() && fi.Mode()&0o111 != 0 {
			f.set(name, fakeCmd{Real: p})
			return
		}
	}
	f.t.Fatalf("no real %s on PATH", name)
}

// remove takes name off PATH, so HasCmd(name) is false.
func (f *fakes) remove(name string) {
	f.t.Helper()
	delete(f.cmds, name)
	f.save()
	for _, d := range []string{f.bin, f.real} {
		if err := os.Remove(filepath.Join(d, name)); err != nil && !os.IsNotExist(err) {
			f.t.Fatal(err)
		}
	}
}

// rawCalls returns each call to a fake, in order, as its name and arguments.
func (f *fakes) rawCalls() [][]string {
	f.t.Helper()
	data, _ := os.ReadFile(filepath.Join(f.dir, "calls"))
	var calls [][]string
	for _, line := range strings.Split(strings.TrimSuffix(string(data), "\n"), "\n") {
		if line == "" {
			continue
		}
		var call []string
		if err := json.Unmarshal([]byte(line), &call); err != nil {
			f.t.Fatalf("call log line %q: %v", line, err)
		}
		calls = append(calls, call)
	}
	return calls
}

// calls returns each call to a fake, in order, as "<name> <args...>".
func (f *fakes) calls() []string {
	var out []string
	for _, c := range f.rawCalls() {
		out = append(out, strings.Join(c, " "))
	}
	return out
}

// unexpected returns the calls to fakes that the test did not set, as calls does.
func (f *fakes) unexpected() []string {
	var out []string
	for _, c := range f.rawCalls() {
		if _, ok := f.cmds[c[0]]; !ok {
			out = append(out, strings.Join(c, " "))
		}
	}
	return out
}

// cancel is an answer that cancels a question, like Esc.
const cancel = "<cancel>"

// kindNames names each Kind in fakeUI.log, such as "note" in "note:   would ...".
var kindNames = map[ui.Kind]string{
	ui.Plain: "plain", ui.Success: "success", ui.Warn: "warn", ui.Fail: "fail", ui.Note: "note",
	ui.Ask: "ask", ui.Step: "step", ui.Heading: "heading", ui.Title: "title", ui.Welcome: "welcome",
}

// fakeUI answers each question from a list and logs every call.
// A question with no answer left fails the test.
// Answers that are left at the end of the test fail it too.
type fakeUI struct {
	t       *testing.T
	answers []string
	// log holds one line for each message line and each question, such as "note:   would ...".
	log []string
}

func newFakeUI(t *testing.T) *fakeUI {
	u := &fakeUI{t: t}
	t.Cleanup(func() {
		if len(u.answers) > 0 {
			t.Errorf("answers left: %q", u.answers)
		}
	})
	return u
}

// answer adds answers.
// Choose takes an option's Value, Confirm takes "yes" or "no", and Input and Write take the text.
// cancel cancels any question.
func (u *fakeUI) answer(answers ...string) { u.answers = append(u.answers, answers...) }

func (u *fakeUI) next(call string) string {
	u.t.Helper()
	u.log = append(u.log, call)
	if len(u.answers) == 0 {
		u.t.Fatalf("no answer left for %q", call)
	}
	a := u.answers[0]
	u.answers = u.answers[1:]
	return a
}

func (u *fakeUI) Print(k ui.Kind, lines ...string) {
	for _, l := range lines {
		u.log = append(u.log, kindNames[k]+": "+l)
	}
}

func (u *fakeUI) Eprint(k ui.Kind, lines ...string) { u.Print(k, lines...) }

func (u *fakeUI) Choose(header string, options ...ui.Option) (string, bool) {
	u.t.Helper()
	a := u.next("choose: " + header)
	if a == cancel {
		return "", false
	}
	if !slices.ContainsFunc(options, func(o ui.Option) bool { return o.Value == a }) {
		u.t.Fatalf("answer %q is not an option of %q: %+v", a, header, options)
	}
	return a, true
}

func (u *fakeUI) Confirm(prompt string, defaultNo bool) (bool, bool) {
	u.t.Helper()
	switch a := u.next("confirm: " + prompt); a {
	case "yes":
		return true, false
	case "no":
		return false, false
	case cancel:
		return false, true
	default:
		u.t.Fatalf("answer %q to %q is not yes, no or cancel", a, prompt)
		return false, false
	}
}

func (u *fakeUI) Input(placeholder, header string) (string, bool) {
	u.t.Helper()
	a := u.next("input: " + header)
	return a, a != cancel
}

func (u *fakeUI) Write(header string) (string, bool) {
	u.t.Helper()
	a := u.next("write: " + header)
	return a, a != cancel
}

// newTestSetup returns a Setup for the profile and mode, in a sandbox, with a fake UI and fake commands.
// Root is this repo, and Tmp is a new temporary folder.
func newTestSetup(t *testing.T, profile, mode string) (*Setup, *fakeUI, *fakes) {
	t.Helper()
	sandbox(t)
	t.Setenv("SHELL", "/bin/bash")
	f := fakeCommands(t)
	u := newFakeUI(t)
	s := &Setup{UI: u, Root: os.Getenv("ENVSETUP_FILES"), Tmp: t.TempDir(), Version: "v0.0.0-test"}
	s.paths()
	// lib/config.sh reads git/gitconfig with git, so the load runs the real git.
	// Then git is a fake that the test did not set again, because git can reach the network.
	f.passThrough("git")
	cfg, err := s.Load(profile, mode, s.UserConfig, true)
	if err != nil {
		t.Fatal(err)
	}
	s.Cfg = cfg
	delete(f.cmds, "git")
	f.save()
	if err := os.Remove(filepath.Join(f.dir, "calls")); err != nil && !os.IsNotExist(err) {
		t.Fatal(err)
	}
	return s, u, f
}

// snapshotHome maps each path under HOME to its content.
// A folder maps to "dir", and a link maps to "-> <target>".
func snapshotHome(t *testing.T) map[string]string {
	t.Helper()
	home := os.Getenv("HOME")
	snap := map[string]string{}
	err := filepath.WalkDir(home, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		switch {
		case d.Type()&fs.ModeSymlink != 0:
			target, err := os.Readlink(p)
			snap[p] = "-> " + target
			return err
		case d.IsDir():
			snap[p] = "dir"
		default:
			data, err := os.ReadFile(p)
			snap[p] = string(data)
			return err
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	return snap
}

// diffSnapshots returns the paths that two snapshots of HOME do not share or that changed, in order.
func diffSnapshots(before, after map[string]string) []string {
	var d []string
	for p, v := range before {
		if w, ok := after[p]; !ok || w != v {
			d = append(d, p)
		}
	}
	for p := range after {
		if _, ok := before[p]; !ok {
			d = append(d, p)
		}
	}
	slices.Sort(d)
	return d
}

// realGit makes git a fake that runs the real git, for a test of git settings.
// git then reads and writes only the sandbox's ~/.gitconfig, and no system config.
func (f *fakes) realGit() {
	f.t.Helper()
	f.t.Setenv("GIT_CONFIG_GLOBAL", os.Getenv("HOME")+"/.gitconfig")
	f.t.Setenv("GIT_CONFIG_NOSYSTEM", "1")
	f.passThrough("git")
}

// writeTestFile writes a file and its folders.
func writeTestFile(t *testing.T, file, text string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(file), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(file, []byte(text), 0o644); err != nil {
		t.Fatal(err)
	}
}

// readTestFile returns the text of a file that must exist.
func readTestFile(t *testing.T, file string) string {
	t.Helper()
	data, err := os.ReadFile(file)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

// checkUILog compares the fake UI's log with want, line for line.
func checkUILog(t *testing.T, got, want []string) {
	t.Helper()
	if !slices.Equal(got, want) {
		t.Errorf("UI log:\n%s\nwant:\n%s", strings.Join(got, "\n"), strings.Join(want, "\n"))
	}
}

// fakeScript makes name a fake that logs each call and then runs the shell script text.
func fakeScript(t *testing.T, f *fakes, name, text string) {
	t.Helper()
	script := filepath.Join(t.TempDir(), name)
	writeTestFile(t, script, "#!/bin/sh\n"+text)
	if err := os.Chmod(script, 0o755); err != nil {
		t.Fatal(err)
	}
	f.set(name, fakeCmd{Real: script})
}

// fakeKeygen makes ssh-keygen a fake that writes a key, like the real one.
// envsetup calls it with -t ed25519 -C <comment> -f <key>.
func fakeKeygen(t *testing.T, f *fakes) {
	t.Helper()
	fakeScript(t, f, "ssh-keygen", "echo private >\"$6\"\necho \"ssh-ed25519 AAAA $4\" >\"$6.pub\"\n")
}

// failingGit makes git exit with code when its arguments contain part.
// Every other call runs the real git, so call it after realGit.
func failingGit(t *testing.T, f *fakes, part string, code int) {
	t.Helper()
	fakeScript(t, f, "git", "case \"$*\" in *'"+part+"'*) exit "+strconv.Itoa(code)+";; esac\nexec '"+f.cmds["git"].Real+"' \"$@\"\n")
}

func TestFakeCommands(t *testing.T) {
	sandbox(t)
	f := fakeCommands(t)
	f.set("curl", fakeCmd{Out: "hello", Code: 3})
	s := &Setup{}
	out, err := s.Output("curl", "-fsSL", "https://example.com")
	if out != "hello" || exitCode(err) != 3 {
		t.Errorf("curl = %q, %v; want hello, exit 3", out, err)
	}
	f.set("echo", fakeCmd{}) // a command that is not guarded
	if out, _ := s.Output("echo", "real"); out != "" {
		t.Errorf("fake echo printed %q", out)
	}
	if err := s.Quiet("sudo", "true"); exitCode(err) != 127 {
		t.Errorf("sudo that the test did not set: %v, want exit 127", err)
	}
	want := []string{"curl -fsSL https://example.com", "echo real", "sudo true"}
	if got := f.calls(); !slices.Equal(got, want) {
		t.Errorf("calls = %q, want %q", got, want)
	}
	if got := f.unexpected(); !slices.Equal(got, []string{"sudo true"}) {
		t.Errorf("unexpected = %q, want the sudo call", got)
	}
	// An argument with a newline or only spaces stays in its call (review finding).
	f.set("gh", fakeCmd{})
	if err := s.Quiet("gh", "a\n  \nb", " "); err != nil {
		t.Fatal(err)
	}
	if got := f.rawCalls(); len(got) != 4 || !slices.Equal(got[3], []string{"gh", "a\n  \nb", " "}) {
		t.Errorf("rawCalls = %q, want the gh call with its 2 arguments last", got)
	}
	f.cmds["sudo"] = fakeCmd{} // the call above was on purpose, so the cleanup passes
	if !HasCmd("bash") || !HasCmd("zsh") {
		t.Error("PATH lost a real command or a fake")
	}
	f.remove("zsh")
	f.remove("bash")
	if HasCmd("zsh") || HasCmd("bash") {
		t.Error("remove left the command on PATH")
	}
}

func TestFakeUI(t *testing.T) {
	u := newFakeUI(t)
	u.answer("b", "yes", cancel, "text")
	if v, ok := u.Choose("Pick", ui.Options("a", "b")...); v != "b" || !ok {
		t.Errorf("Choose = %q, %v", v, ok)
	}
	if yes, cancelled := u.Confirm("Sure?", true); !yes || cancelled {
		t.Errorf("Confirm = %v, %v", yes, cancelled)
	}
	if _, cancelled := u.Confirm("Again?", true); !cancelled {
		t.Error("cancel did not cancel")
	}
	if v, ok := u.Input("", "Name"); v != "text" || !ok {
		t.Errorf("Input = %q, %v", v, ok)
	}
	u.Print(ui.Warn, "one", "two")
	want := []string{"choose: Pick", "confirm: Sure?", "confirm: Again?", "input: Name", "warn: one", "warn: two"}
	if !slices.Equal(u.log, want) {
		t.Errorf("log = %q, want %q", u.log, want)
	}
}

func TestSnapshotHome(t *testing.T) {
	home := sandbox(t)
	if err := os.WriteFile(home+"/a", []byte("1"), 0o644); err != nil {
		t.Fatal(err)
	}
	before := snapshotHome(t)
	if before[home+"/a"] != "1" || before[home] != "dir" {
		t.Fatalf("snapshot = %q", before)
	}
	if err := os.Symlink("a", home+"/l"); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(home+"/a", []byte("2"), 0o644); err != nil {
		t.Fatal(err)
	}
	after := snapshotHome(t)
	if after[home+"/l"] != "-> a" {
		t.Errorf("snapshot of a link = %q", after[home+"/l"])
	}
	if d := diffSnapshots(before, after); !slices.Equal(d, []string{home + "/a", home + "/l"}) {
		t.Errorf("diffSnapshots = %q, want the changed file and the new link", d)
	}
}

// TestSetUpZshDryRun shows how to use the helpers: a dry run of an action.
func TestSetUpZshDryRun(t *testing.T) {
	s, u, f := newTestSetup(t, "home", "full")
	s.DryRun = true
	f.remove("zsh")
	if err := os.WriteFile(s.Home+"/.zshrc", []byte("# mine\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	before := snapshotHome(t)
	if err := s.SetUpZsh(); err != nil {
		t.Fatal(err)
	}
	want := []string{
		"note:   would install zsh (as root)",
		"note:   would ask to make zsh your login shell (chsh)",
		"note:   would install oh-my-zsh with its installer from github.com",
		"note:   would copy shell/ (v0.0.0-test) to " + s.Data + ", which new shells load",
		"note:   would add a 5-line block to " + s.Home + "/.zshrc that loads shell/ from " + s.Data,
	}
	if !slices.Equal(u.log, want) {
		t.Errorf("UI log:\n%s\nwant:\n%s", strings.Join(u.log, "\n"), strings.Join(want, "\n"))
	}
	if d := diffSnapshots(before, snapshotHome(t)); len(d) > 0 {
		t.Errorf("the dry run changed HOME: %q", d)
	}
	if c := f.calls(); len(c) > 0 {
		t.Errorf("the dry run ran %q", c)
	}
}
