package ui

import (
	"bytes"
	"io"
	"strings"
	"testing"
)

// The expected texts come from gum v2.0.2 with CLICOLOR_FORCE=1 and TERM=xterm-256color.
func TestStyleRender(t *testing.T) {
	for _, tc := range []struct {
		name  string
		style Style
		lines []string
		want  string
	}{
		{"plain", nil, []string{"hi"}, "hi"},
		{"bright color", Style{Fg(12)}, []string{"hi"}, "\x1b[94mhi\x1b[m"},
		{
			"color and bold pad each line", Style{Fg(2), Bold}, []string{"Hello", "wide line"},
			"\x1b[1;32mHello\x1b[m    \n\x1b[1;32mwide line\x1b[m",
		},
		{
			"rounded border with padding", Style{Border("rounded"), Padding(1, 2), Fg(1)}, []string{"a", "bb"},
			"╭──────╮\n│      │\n│  \x1b[31ma\x1b[m   │\n│  \x1b[31mbb\x1b[m  │\n│      │\n╰──────╯",
		},
		{
			"normal border", Style{Border("normal"), Padding(0, 1)}, []string{"x", "yy"},
			"┌────┐\n│ x  │\n│ yy │\n└────┘",
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got := tc.style.lipgloss().Render(strings.Join(tc.lines, "\n"))
			if got != tc.want {
				t.Errorf("got %q, want %q", got, tc.want)
			}
		})
	}
}

func TestPrintColor(t *testing.T) {
	st := Style{Fg(12), Bold}
	for _, tc := range []struct {
		name string
		env  map[string]string
		want string
	}{
		{"not a terminal", nil, "hi\n"},
		{"NO_COLOR keeps bold", map[string]string{"TTY_FORCE": "1", "TERM": "xterm-256color", "NO_COLOR": "1"}, "\x1b[1mhi\x1b[m\n"},
		{"terminal", map[string]string{"TTY_FORCE": "1", "TERM": "xterm-256color"}, "\x1b[1;94mhi\x1b[m\n"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Setenv("NO_COLOR", "")
			t.Setenv("TTY_FORCE", "")
			t.Setenv("CLICOLOR_FORCE", "")
			for k, v := range tc.env {
				t.Setenv(k, v)
			}
			var buf bytes.Buffer
			term{}.print(&buf, st, []string{"hi"})
			if buf.String() != tc.want {
				t.Errorf("got %q, want %q", buf.String(), tc.want)
			}
		})
	}
}

// keys returns a term that reads the given keys and draws nowhere.
func keys(s string) term { return term{in: strings.NewReader(s), out: io.Discard} }

func TestChoose(t *testing.T) {
	opts := []string{"a", "b", "c"}
	for _, tc := range []struct {
		keys   string
		want   string
		wantOK bool
	}{
		{"\r", "a", true},
		{"j\r", "b", true},
		{"\x1b[B\x1b[B\r", "c", true}, // the down arrow
		{"jjk\r", "b", true},
		{"/j\r", "b", true}, // gum choose has no filter, so "/" does nothing
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
