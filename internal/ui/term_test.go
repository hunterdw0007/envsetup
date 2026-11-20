package ui

import (
	"bytes"
	"io"
	"os"
	"regexp"
	"strings"
	"testing"
)

// ansi matches the escape codes of colors and text styles.
var ansi = regexp.MustCompile("\x1b\\[[0-9;]*m")

// TestTheme checks that every kind of message keeps its text, and that each kind looks different from plain text.
func TestTheme(t *testing.T) {
	t.Setenv("TTY_FORCE", "1")
	t.Setenv("TERM", "xterm-256color")
	t.Setenv("NO_COLOR", "")
	for k := Plain; k <= Welcome; k++ {
		var buf bytes.Buffer
		term{}.print(&buf, k, []string{"first", "second"})
		out := buf.String()
		if plain := ansi.ReplaceAllString(out, ""); !strings.Contains(plain, "first") || !strings.Contains(plain, "second") {
			t.Errorf("kind %d lost its text: %q", k, out)
		}
		if k != Plain && out == "first\nsecond\n" {
			t.Errorf("kind %d has no look of its own", k)
		}
	}
}

func TestPrintColor(t *testing.T) {
	for _, tc := range []struct {
		name      string
		env       map[string]string
		wantColor bool
	}{
		{"not a terminal", nil, false},
		{"NO_COLOR", map[string]string{"TTY_FORCE": "1", "TERM": "xterm-256color", "NO_COLOR": "1"}, false},
		{"terminal", map[string]string{"TTY_FORCE": "1", "TERM": "xterm-256color"}, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Setenv("NO_COLOR", "")
			t.Setenv("TTY_FORCE", "")
			t.Setenv("CLICOLOR_FORCE", "")
			for k, v := range tc.env {
				t.Setenv(k, v)
			}
			var buf bytes.Buffer
			term{}.print(&buf, Success, []string{"hi"})
			hasColor := strings.Contains(buf.String(), "38;")
			if hasColor != tc.wantColor || ansi.ReplaceAllString(buf.String(), "") != "hi\n" {
				t.Errorf("got %q, want color %v", buf.String(), tc.wantColor)
			}
		})
	}
}

// keys returns a term that reads the given keys and draws nowhere.
func keys(s string) term { return term{in: strings.NewReader(s), out: io.Discard} }

// TestMain gives the form tests a full terminal type.
// TestDumbTerminal covers TERM=dumb, where huh asks in plain text.
func TestMain(m *testing.M) {
	os.Setenv("TERM", "xterm-256color")
	os.Exit(m.Run())
}

// TestDumbTerminal checks the plain-text questions that huh asks for TERM=dumb (accessible mode).
func TestDumbTerminal(t *testing.T) {
	t.Setenv("TERM", "dumb")
	if got, ok := keys("2\n").Choose("Pick", Options("a", "b")...); !ok || got != "b" {
		t.Errorf("Choose 2: got (%q, %v), want (b, true)", got, ok)
	}
	// huh v2.0.3 panics here, and run turns the panic into a cancel.
	if got, ok := keys("j\r").Choose("Pick", Options("a", "b")...); ok {
		t.Errorf("Choose with no number before the end of input: got (%q, true), want a cancel", got)
	}
}

func TestChoose(t *testing.T) {
	opts := Options("a", "b", "c")
	for _, tc := range []struct {
		keys   string
		want   string
		wantOK bool
	}{
		{"\r", "a", true},
		{"j\r", "b", true},
		{"\x1b[B\x1b[B\r", "c", true}, // the down arrow
		{"jjk\r", "b", true},
		{"/j\r", "b", true}, // the filter is off, so "/" does nothing
		{"j\x1b", "", false},
		{"\x03", "", false}, // ctrl+c
	} {
		got, ok := keys(tc.keys).Choose("Pick", opts...)
		if got != tc.want || ok != tc.wantOK {
			t.Errorf("keys %q: got (%q, %v), want (%q, %v)", tc.keys, got, ok, tc.want, tc.wantOK)
		}
	}
}

func TestConfirm(t *testing.T) {
	for _, tc := range []struct {
		keys          string
		defaultNo     bool
		yes, canceled bool
	}{
		{"\r", false, true, false},
		{"\r", true, false, false},
		{"y", true, true, false},
		{"n", false, false, false},
		{"\x1b", false, false, true},
		{"\x03", true, false, true},
	} {
		yes, canceled := keys(tc.keys).Confirm("Sure?", tc.defaultNo)
		if yes != tc.yes || canceled != tc.canceled {
			t.Errorf("keys %q, defaultNo %v: got (%v, %v), want (%v, %v)", tc.keys, tc.defaultNo, yes, canceled, tc.yes, tc.canceled)
		}
	}
}

func TestInputAndWrite(t *testing.T) {
	if got, ok := keys("Jane Doe\r").Input("Your name", ""); got != "Jane Doe" || !ok {
		t.Errorf("Input: got (%q, %v)", got, ok)
	}
	if got, ok := keys("\r").Input("Your name", "Name"); got != "" || !ok {
		t.Errorf("Input with no text: got (%q, %v)", got, ok)
	}
	if got, ok := keys("Jane\x1b").Input("Your name", ""); got != "" || ok {
		t.Errorf("Input cancelled: got (%q, %v)", got, ok)
	}
	// ctrl+j (\n) adds a line, and enter (\r) saves.
	if got, ok := keys("[a]\nb = 1\n\n\r").Write("Config"); got != "[a]\nb = 1" || !ok {
		t.Errorf("Write: got (%q, %v)", got, ok)
	}
	if got, ok := keys("text\x1b").Write("Config"); got != "" || ok {
		t.Errorf("Write cancelled: got (%q, %v)", got, ok)
	}
}
