package setup

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

// This file tests "Move dotfiles to XDG dirs" (XDGTidy) and its uninstall (xdgRestore).

// xdgNote is one file of a program in xdg-ninja's notes.
type xdgNote struct{ program, path, help string }

// xdgFence wraps the lines in a code block, like xdg-ninja's notes.
func xdgFence(lines ...string) string {
	return "Text:\n\n```bash\n" + strings.Join(lines, "\n") + "\n```\n"
}

// xdgSetup returns a Setup with jq, a fake git and these notes in the cache, as a clone.
func xdgSetup(t *testing.T, notes ...xdgNote) (*Setup, *fakeUI, *fakes) {
	t.Helper()
	if !HasCmd("jq") {
		t.Skip("needs jq")
	}
	s, u, f := newTestSetup(t, "home", "full")
	f.set("git", fakeCmd{})
	if len(notes) > 0 {
		writeNotes(t, s, notes...)
	}
	return s, u, f
}

func writeNotes(t *testing.T, s *Setup, notes ...xdgNote) {
	t.Helper()
	dir := s.xdgCache() + "/programs"
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(s.xdgCache()+"/.git", 0o755); err != nil {
		t.Fatal(err)
	}
	for _, n := range notes {
		data, _ := json.Marshal(map[string]any{
			"name":  n.program,
			"files": []map[string]any{{"path": n.path, "movable": true, "help": n.help}},
		})
		if err := os.WriteFile(filepath.Join(dir, n.program+".json"), data, 0o644); err != nil {
			t.Fatal(err)
		}
	}
}

// xdgLogged reports whether a line of the UI log contains the text.
func xdgLogged(u *fakeUI, text string) bool {
	return slices.ContainsFunc(u.log, func(l string) bool { return strings.Contains(l, text) })
}

func xdgWrite(t *testing.T, p, text string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, []byte(text), 0o644); err != nil {
		t.Fatal(err)
	}
}

func xdgRead(p string) string {
	b, _ := os.ReadFile(p)
	return string(b)
}

func TestXDGTidy(t *testing.T) {
	s, u, f := xdgSetup(t,
		xdgNote{"foo", "$HOME/.foorc", xdgFence(`export FOORC="$XDG_CONFIG_HOME"/foo/foorc`)},
		xdgNote{"bar", "$HOME/.bar", "You can move the file to _$XDG_DATA_HOME/bar_."},
	)
	xdgWrite(t, s.Home+"/.foorc", "foo data")
	xdgWrite(t, s.Home+"/.bar", "bar data")
	foo, bar := s.Home+"/.config/foo/foorc", s.Home+"/.local/share/bar"

	// Dry run: nothing changes, and the action says what it would move.
	s.DryRun = true
	before := snapshotHome(t)
	if err := s.XDGTidy(); err != nil {
		t.Fatal(err)
	}
	// The notes come in the order of their file names.
	want := []string{
		"note:   would move ~/.bar to ~/.local/share/bar",
		"note:   would move ~/.foorc to ~/.config/foo/foorc and export FOORC",
	}
	if !slices.Equal(u.log, want) {
		t.Errorf("dry run log = %q, want %q", u.log, want)
	}
	if d := diffSnapshots(before, snapshotHome(t)); len(d) > 0 {
		t.Errorf("the dry run changed HOME: %q", d)
	}
	if c := f.calls(); len(c) > 0 {
		t.Errorf("the dry run ran %q", c)
	}

	// A "no" moves nothing.
	s.DryRun = false
	u.answer("no")
	if err := s.XDGTidy(); err != nil {
		t.Fatal(err)
	}
	if d := diffSnapshots(before, snapshotHome(t)); len(d) > 0 {
		t.Errorf("a no changed HOME: %q", d)
	}

	// First run: the action moves both files, records them and writes the export.
	u.answer("yes")
	if err := s.XDGTidy(); err != nil {
		t.Fatal(err)
	}
	if xdgRead(foo) != "foo data" || xdgRead(bar) != "bar data" || exists(s.Home+"/.foorc") || exists(s.Home+"/.bar") {
		t.Error("the files did not move")
	}
	wantMoves := s.Home + "/.bar\t" + bar + "\t\n" + s.Home + "/.foorc\t" + foo + "\tFOORC\n"
	if got := xdgRead(s.xdgMoves()); got != wantMoves {
		t.Errorf("xdg-moves = %q, want %q", got, wantMoves)
	}
	if got := xdgRead(s.xdgEnv()); !strings.Contains(got, "export FOORC="+Quote(foo)+"\n") || strings.Count(got, "export ") != 1 {
		t.Errorf("xdg.sh = %q, want one export of FOORC", got)
	}
	pull := "git -C " + s.xdgCache() + " pull -q --ff-only"
	if c := f.calls(); !slices.Equal(c, []string{pull, pull}) {
		t.Errorf("calls = %q, want two pulls", c)
	}

	// Second run: nothing is left to move.
	moved := snapshotHome(t)
	if err := s.XDGTidy(); err != nil {
		t.Fatal(err)
	}
	if u.log[len(u.log)-1] != "plain: No dotfiles to move." {
		t.Errorf("second run log ends with %q", u.log[len(u.log)-1])
	}
	if d := diffSnapshots(moved, snapshotHome(t)); len(d) > 0 {
		t.Errorf("the second run changed HOME: %q", d)
	}

	// Uninstall moves both files back and deletes the record, the exports and the notes.
	f.set("git", fakeCmd{Code: 1}) // ~/.gitconfig includes nothing
	u.answer("yes")
	if err := s.Uninstall(); err != nil {
		t.Fatal(err)
	}
	if xdgRead(s.Home+"/.foorc") != "foo data" || xdgRead(s.Home+"/.bar") != "bar data" {
		t.Error("Uninstall did not move the files back")
	}
	for _, p := range []string{foo, filepath.Dir(foo), bar, s.xdgMoves(), s.xdgEnv(), s.xdgCache()} {
		if exists(p) {
			t.Errorf("Uninstall left %s", p)
		}
	}
}

// TestXDGTidyFailedMove moves one file, and fails to move another into a folder that it cannot write.
func TestXDGTidyFailedMove(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("root can write to a closed folder")
	}
	s, u, _ := xdgSetup(t,
		xdgNote{"bar", "$HOME/.bar", "You can move the file to _$XDG_DATA_HOME/bar_."},
		xdgNote{"foo", "$HOME/.foorc", xdgFence(`export FOORC="$XDG_CONFIG_HOME"/foo/foorc`)},
	)
	xdgWrite(t, s.Home+"/.foorc", "foo data")
	xdgWrite(t, s.Home+"/.bar", "bar data")
	// The state folder is in ~/.config, so the closed folder is ~/.local/share.
	if err := os.MkdirAll(s.Home+"/.local/share", 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(s.Home+"/.local/share", 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.Chmod(s.Home+"/.local/share", 0o755) })
	u.answer("yes")
	if err := s.XDGTidy(); !errors.Is(err, ErrFailed) {
		t.Errorf("XDGTidy = %v, want ErrFailed", err)
	}
	if !xdgLogged(u, "fail: Couldn't move "+s.Home+"/.bar") || xdgRead(s.Home+"/.bar") != "bar data" {
		t.Errorf("log = %q, want .bar left in place", u.log)
	}
	// Only the move that worked is in the record.
	foo := s.Home + "/.config/foo/foorc"
	if got, want := xdgRead(s.xdgMoves()), s.Home+"/.foorc\t"+foo+"\tFOORC\n"; got != want {
		t.Errorf("xdg-moves = %q, want %q", got, want)
	}
}

func TestXDGTidyNeedsTools(t *testing.T) {
	s, u, f := xdgSetup(t)
	f.remove("jq")
	if err := s.XDGTidy(); err != nil || !xdgLogged(u, "Moving dotfiles needs jq and git.") {
		t.Errorf("XDGTidy without jq = %v, log %q", err, u.log)
	}
}

func TestXDGFetch(t *testing.T) {
	s, u, f := xdgSetup(t)
	clone := "git clone -q --depth 1 https://github.com/b3nj5m1n/xdg-ninja " + s.xdgCache()

	// Dry run without notes: it says what it would download.
	s.DryRun = true
	if s.xdgFetch() || !xdgLogged(u, "would download xdg-ninja's notes into "+s.xdgCache()) {
		t.Errorf("dry run: log %q", u.log)
	}

	// A failed download changes nothing, except the empty folder for the notes.
	s.DryRun = false
	f.set("git", fakeCmd{Code: 128})
	before := snapshotHome(t)
	if err := s.XDGTidy(); err != nil {
		t.Fatal(err)
	}
	if !xdgLogged(u, "fail: Couldn't download xdg-ninja's notes from https://github.com/b3nj5m1n/xdg-ninja") {
		t.Errorf("log = %q", u.log)
	}
	if d := diffSnapshots(before, snapshotHome(t)); len(d) > 2 || (len(d) > 0 && !strings.HasPrefix(s.CacheDir(), d[len(d)-1])) {
		t.Errorf("a failed download changed HOME: %q", d)
	}
	if exists(s.xdgCache()) || exists(s.xdgMoves()) || exists(s.xdgEnv()) {
		t.Error("a failed download left notes or a record")
	}

	// ENVSETUP_XDG_NINJA_URL names another copy.
	t.Setenv("ENVSETUP_XDG_NINJA_URL", "file:///srv/xdg-ninja")
	f.set("git", fakeCmd{})
	if !s.xdgFetch() {
		t.Error("xdgFetch after a clone = false")
	}
	wantClone := "git clone -q --depth 1 file:///srv/xdg-ninja " + s.xdgCache()
	if c := f.calls(); len(c) != 2 || c[0] != clone || c[1] != wantClone {
		t.Errorf("calls = %q, want %q, then %q", c, clone, wantClone)
	}

	// A failed update uses the copy from last time.
	writeNotes(t, s)
	f.set("git", fakeCmd{Code: 1})
	if !s.xdgFetch() || !xdgLogged(u, "Couldn't update xdg-ninja's notes. Using the copy from last time.") {
		t.Errorf("failed pull: log %q", u.log)
	}
}

func TestXDGPlanSkips(t *testing.T) {
	export := func(v, path string) string { return xdgFence(`export ` + v + `="$XDG_CONFIG_HOME"/` + path) }
	s, u, _ := xdgSetup(t,
		xdgNote{"link", "$HOME/.link", export("LINKRC", "link")},
		xdgNote{"git", "$HOME/.gitconfig", export("GITCONF", "git/config")},
		xdgNote{"manual", "$HOME/.manual", xdgFence("export A=1", "export B=2")},
		xdgNote{"hist", "$HOME/.hist", export("HISTFILE", "hist")},
		xdgNote{"set", "$HOME/.setrc", export("SETRC", "set")},
		xdgNote{"there", "$HOME/.there", export("THERE", "there")},
		xdgNote{"twoa", "$HOME/.twoa", export("TWO", "twoa")},
		xdgNote{"twob", "$HOME/.twob", export("TWO", "twob")},
		xdgNote{"named", "$HOME/.named", export("NAMED", "named")},
		xdgNote{"deep", "$HOME/.local/deep", export("DEEP", "deep")},
		xdgNote{"absent", "$HOME/.absent", export("ABSENT", "absent")},
	)
	for _, name := range []string{".gitconfig", ".manual", ".hist", ".setrc", ".there", ".twoa", ".twob", ".named", ".local/deep"} {
		xdgWrite(t, s.Home+"/"+name, "x")
	}
	xdgWrite(t, s.Home+"/.config/there", "already")
	if err := os.Symlink(".named", s.Home+"/.link"); err != nil {
		t.Fatal(err)
	}
	xdgWrite(t, s.Home+"/.bashrc", "source ~/.named\n")
	t.Setenv("SETRC", "/elsewhere")

	skips, moves := s.xdgPlan()
	if len(moves) > 0 {
		t.Errorf("moves = %+v, want none", moves)
	}
	got := map[string]string{}
	for _, it := range skips {
		got[it.name] = it.reason
	}
	want := map[string]string{
		"link":   "it is a symlink, so something else may manage it",
		"git":    "a shell or envsetup reads it at startup",
		"manual": "needs manual steps (see xdg-ninja)",
		"hist":   "$HISTFILE is shared with other programs",
		"set":    "$SETRC is already set",
		"there":  s.Home + "/.config/there already exists",
		"twoa":   "more than one program uses $TWO",
		"twob":   "more than one program uses $TWO",
		"named":  "referenced from " + s.Home + "/.bashrc",
	}
	for name, reason := range want {
		if got[name] != reason {
			t.Errorf("%s: reason %q, want %q", name, got[name], reason)
		}
	}
	if len(got) != len(want) {
		t.Errorf("skips = %q, want only %d", got, len(want))
	}

	// XDGTidy lists each skip, with ~ for HOME.
	if err := s.XDGTidy(); err != nil {
		t.Fatal(err)
	}
	if !xdgLogged(u, "warn:   leaving ~/.there (there): ~/.config/there already exists") {
		t.Errorf("log = %q", u.log)
	}
}

func TestReferencedFrom(t *testing.T) {
	dir := t.TempDir()
	rcs := []string{dir + "/a", dir + "/b", dir + "/c", dir + "/d", dir + "/missing"}
	xdgWrite(t, rcs[0], "x ~/.foo\n")
	xdgWrite(t, rcs[1], "x $HOME/.foo\n")
	xdgWrite(t, rcs[2], "x ${HOME}/.foo\n")
	xdgWrite(t, rcs[3], "x /h/.foo ~/.foobar\n")
	if got, want := referencedFrom(rcs, ".foo", "/h/.foo"), strings.Join(rcs[:4], ", "); got != want {
		t.Errorf("referencedFrom = %q, want %q", got, want)
	}
	if got := referencedFrom(rcs[:1], ".bar", "/h/.bar"); got != "" {
		t.Errorf("referencedFrom = %q, want empty", got)
	}
}

func TestTilde(t *testing.T) {
	s := &Setup{Home: "/home/me"}
	for in, want := range map[string]string{"/home/me/.a": "~/.a", "/home/me": "~", "/etc/a": "/etc/a"} {
		if got := s.tilde(in); got != want {
			t.Errorf("tilde(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestXDGWriteEnv(t *testing.T) {
	s, _, _ := xdgSetup(t)
	if err := s.xdgWriteEnv(); err == nil {
		t.Error("xdgWriteEnv without xdg-moves = nil, want an error")
	}
}

func TestXDGRestore(t *testing.T) {
	s, u, _ := xdgSetup(t)
	a, b := s.Home+"/.a", s.Home+"/.b"
	newA, newB := s.Home+"/.config/a/arc", s.Home+"/.config/b"
	xdgWrite(t, newA, "a")
	xdgWrite(t, newB, "b")
	xdgWrite(t, b, "b again") // the program made a new .b
	xdgWrite(t, s.xdgMoves(), a+"\t"+newA+"\tARC\n"+b+"\t"+newB+"\tBRC\n"+s.Home+"/.gone\t"+s.Home+"/.config/gone\t\n")
	xdgWrite(t, s.xdgEnv(), "old\n")

	// Dry run: nothing changes.
	s.DryRun = true
	before := snapshotHome(t)
	if err := s.xdgRestore(); err != nil {
		t.Errorf("dry run = %v", err)
	}
	if !xdgLogged(u, "note:   would move "+newA+" back to "+a) || !xdgLogged(u, "Leaving "+newB) {
		t.Errorf("dry run log = %q", u.log)
	}
	if d := diffSnapshots(before, snapshotHome(t)); len(d) > 0 {
		t.Errorf("the dry run changed HOME: %q", d)
	}

	// .a moves back, and .b stays with its record and its export.
	s.DryRun = false
	if err := s.xdgRestore(); !errors.Is(err, ErrFailed) {
		t.Errorf("xdgRestore = %v, want ErrFailed for .b", err)
	}
	if xdgRead(a) != "a" || exists(newA) || exists(filepath.Dir(newA)) {
		t.Error(".a did not move back, or its folder stayed")
	}
	if xdgRead(newB) != "b" || xdgRead(b) != "b again" {
		t.Error(".b changed")
	}
	if got, want := xdgRead(s.xdgMoves()), b+"\t"+newB+"\tBRC\n"; got != want {
		t.Errorf("xdg-moves = %q, want %q", got, want)
	}
	if got := xdgRead(s.xdgEnv()); !strings.Contains(got, "export BRC=") || strings.Contains(got, "ARC") {
		t.Errorf("xdg.sh = %q, want only the export of BRC", got)
	}
	if !xdgLogged(u, "Leaving "+newB+" where it is: "+b+" exists again.") {
		t.Errorf("log = %q", u.log)
	}

	// After the user deletes the new .b, a second run moves it back and deletes the rest.
	if err := os.Remove(b); err != nil {
		t.Fatal(err)
	}
	if err := s.xdgRestore(); err != nil {
		t.Fatal(err)
	}
	if xdgRead(b) != "b" || exists(s.xdgMoves()) || exists(s.xdgEnv()) {
		t.Error("the second run did not finish the restore")
	}
}

// TestXDGTidyRepairsExports checks #159.
// A Ctrl-C after a move leaves the move in xdg-moves, but not its export in xdg.sh.
// The next run must write the export again.
func TestXDGTidyRepairsExports(t *testing.T) {
	t.Skip("#159")
	s, _, _ := xdgSetup(t, xdgNote{"foo", "$HOME/.foorc", xdgFence(`export FOORC="$XDG_CONFIG_HOME"/foo/foorc`)})
	foo := s.Home + "/.config/foo/foorc"
	xdgWrite(t, foo, "foo data")
	xdgWrite(t, s.xdgMoves(), s.Home+"/.foorc\t"+foo+"\tFOORC\n")
	if err := s.XDGTidy(); err != nil {
		t.Fatal(err)
	}
	if got := xdgRead(s.xdgEnv()); !strings.Contains(got, "export FOORC="+Quote(foo)) {
		t.Errorf("xdg.sh = %q, want the export of FOORC", got)
	}
}
