package setup

import (
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

// The fuzz tests feed random input to the functions that edit user files or read text from bash.
// Their seed inputs are in testdata/fuzz/<FuzzX>/.
// go test runs each target with its seeds only.
// go test -fuzz=FuzzX -fuzztime=60s runs one target with random input.

// FuzzRemoveRCBlock builds a file of text a, one envsetup block with text b, and text c.
func FuzzRemoveRCBlock(f *testing.F) {
	f.Fuzz(func(t *testing.T, a, b, c string) {
		for _, s := range []*string{&a, &b} {
			if *s != "" && !strings.HasSuffix(*s, "\n") {
				*s += "\n"
			}
		}
		file := filepath.Join(t.TempDir(), "rc")
		remove := func() string {
			t.Helper()
			if err := RemoveRCBlock(file, ""); err != nil {
				t.Fatal(err)
			}
			out, _ := os.ReadFile(file)
			return string(out)
		}
		in := a + RCBegin + "\n" + b + RCEnd + "\n" + c
		if err := os.WriteFile(file, []byte(in), 0o600); err != nil {
			t.Fatal(err)
		}
		once := remove()
		if twice := remove(); twice != once {
			t.Errorf("a second run changed %q to %q", once, twice)
		}
		// With markers only around b, every line of a and c stays, in the same order.
		hasMarker := func(s string) bool {
			lines := splitLines(s)
			return slices.Contains(lines, RCBegin) || slices.Contains(lines, RCEnd)
		}
		if hasMarker(a) || hasMarker(b) || hasMarker(c) {
			return
		}
		want := ""
		if a+c != "" {
			want = strings.Join(splitLines(a+c), "\n") + "\n"
		}
		if once != want {
			t.Errorf("RemoveRCBlock(%q) = %q, want %q", in, once, want)
		}
	})
}

func FuzzRenameWords(f *testing.F) {
	items := []string{"ENVSETUP_OLD=ENVSETUP_NEW", "ENVSETUP_NEW=ENVSETUP_NEWER"}
	f.Fuzz(func(t *testing.T, text string) {
		once := renameWords(text, items)
		if twice := renameWords(once, items); twice != once {
			t.Errorf("a second run changed %q to %q", once, twice)
		}
		// Only a whole word that is an old name changes, so a longer word stays.
		in, out := words.FindAllString(text, -1), words.FindAllString(once, -1)
		if len(in) != len(out) {
			t.Fatalf("renameWords(%q) = %q has other word boundaries", text, once)
		}
		for i := range in {
			if in[i] != out[i] && in[i] != "ENVSETUP_OLD" && in[i] != "ENVSETUP_NEW" {
				t.Errorf("renameWords(%q) changed %q to %q", text, in[i], out[i])
			}
		}
	})
}

func FuzzParseDump(f *testing.F) {
	f.Fuzz(func(t *testing.T, data []byte) {
		for name := range parseDump(data) {
			if !strings.Contains(string(data), name) {
				t.Errorf("parseDump(%q) returned the key %q, which is not in the input", data, name)
			}
		}
	})
}

func FuzzVersionCompare(f *testing.F) {
	f.Fuzz(func(t *testing.T, a, b string) {
		if versionCompare(a, a) != 0 || verrevcmp(a, a) != 0 {
			t.Errorf("%q does not equal itself", a)
		}
		if sign(versionCompare(a, b)) != -sign(versionCompare(b, a)) {
			t.Errorf("versionCompare(%q, %q) is not the reverse of versionCompare(%q, %q)", a, b, b, a)
		}
		if sign(verrevcmp(a, b)) != -sign(verrevcmp(b, a)) {
			t.Errorf("verrevcmp(%q, %q) is not the reverse of verrevcmp(%q, %q)", a, b, b, a)
		}
	})
}

func FuzzXDGTarget(f *testing.F) {
	sandbox(f)
	home := os.Getenv("HOME")
	f.Fuzz(func(t *testing.T, help string) {
		target, _, ok := xdgTarget(help)
		if !ok && target != "" {
			t.Errorf("xdgTarget(%q) = %q, want empty when not ok", help, target)
		}
		if ok && !strings.HasPrefix(filepath.Clean(target), home+"/") {
			t.Errorf("xdgTarget(%q) = %q, which is not under %s", help, target, home)
		}
	})
}
