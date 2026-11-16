package ui

import (
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// capture returns what fn writes to *f, which is os.Stdout or os.Stderr.
func capture(t *testing.T, f **os.File, fn func()) string {
	t.Helper()
	tmp, err := os.CreateTemp(t.TempDir(), "out")
	if err != nil {
		t.Fatal(err)
	}
	defer tmp.Close()
	old := *f
	*f = tmp
	defer func() { *f = old }()
	fn()
	data, err := os.ReadFile(tmp.Name())
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

// result is what one call gave: the text that $(gum ...) would hold, and whether gum exited 0.
type result struct {
	out string
	ok  bool
}

// TestScriptMatchesFakeGum runs each call on the scripted UI and on tests/gum.sh.
// Both must log the same line, give the same text and succeed or fail alike.
func TestScriptMatchesFakeGum(t *testing.T) {
	gum, err := filepath.Abs("../../tests/gum.sh")
	if err != nil {
		t.Fatal(err)
	}
	unset := "<unset>"
	for _, tc := range []struct {
		name     string
		choices  string
		confirms string
		input    string // unset leaves SMOKE_INPUT out of the environment
		write    string // unset leaves SMOKE_WRITE out of the environment
		args     []string
		call     func(t *testing.T, u UI) result
	}{
		{
			name: "choose with a header", choices: "two words\nb\n",
			args: []string{"choose", "--header", "Pick one", "two words", "b"},
			call: func(_ *testing.T, u UI) result { return pick(u.Choose("Pick one", "two words", "b")) },
		},
		{
			name: "choose without a header", choices: "b\n",
			args: []string{"choose", "a", "b"},
			call: func(_ *testing.T, u UI) result { return pick(u.Choose("", "a", "b")) },
		},
		{
			name: "choose ESC", choices: "ESC\nb\n",
			args: []string{"choose", "a", "b"},
			call: func(_ *testing.T, u UI) result { return pick(u.Choose("", "a", "b")) },
		},
		{
			name: "choose with no answer left",
			args: []string{"choose", "a"},
			call: func(_ *testing.T, u UI) result { return pick(u.Choose("", "a")) },
		},
		{
			name: "choose with an empty answer", choices: "\na\n",
			args: []string{"choose", "a"},
			call: func(_ *testing.T, u UI) result { return pick(u.Choose("", "a")) },
		},
		{
			name: "choose with an unknown signal", choices: "SIGFOO\n",
			args: []string{"choose", "a"},
			call: func(_ *testing.T, u UI) result { return pick(u.Choose("", "a")) },
		},
		{
			name: "confirm yes", confirms: "yes\n",
			args: []string{"confirm", "Sure?"},
			call: func(t *testing.T, u UI) result { return confirm(t, u, "Sure?", false) },
		},
		{
			name: "confirm no", confirms: "no\nyes\n",
			args: []string{"confirm", "--default=false", "Sure?"},
			call: func(t *testing.T, u UI) result { return confirm(t, u, "Sure?", true) },
		},
		{
			name: "confirm with no answer left",
			args: []string{"confirm", "Sure?"},
			call: func(t *testing.T, u UI) result { return confirm(t, u, "Sure?", false) },
		},
		{
			name: "input name", input: unset,
			args: []string{"input", "--placeholder", "Your name"},
			call: func(_ *testing.T, u UI) result { return pick(u.Input("Your name", "")) },
		},
		{
			name: "input email with a header", input: unset,
			args: []string{"input", "--placeholder", "you@example.com", "--header", "Git email"},
			call: func(_ *testing.T, u UI) result { return pick(u.Input("you@example.com", "Git email")) },
		},
		{
			name: "input @ in the header only", input: unset,
			args: []string{"input", "--placeholder", "name", "--header", "a@b"},
			call: func(_ *testing.T, u UI) result { return pick(u.Input("name", "a@b")) },
		},
		{
			name: "input SMOKE_INPUT", input: "Jane Doe\n\n",
			args: []string{"input", "--placeholder", "you@example.com"},
			call: func(_ *testing.T, u UI) result { return pick(u.Input("you@example.com", "")) },
		},
		{
			name: "input empty SMOKE_INPUT", input: "",
			args: []string{"input", "--placeholder", "Your name"},
			call: func(_ *testing.T, u UI) result { return pick(u.Input("Your name", "")) },
		},
		{
			name: "input ESC", input: "ESC",
			args: []string{"input", "--placeholder", "Your name"},
			call: func(_ *testing.T, u UI) result { return pick(u.Input("Your name", "")) },
		},
		{
			name: "write", input: unset, write: "[a]\n\tb = 1\n\n",
			args: []string{"write", "--char-limit", "0", "--height", "15", "--show-line-numbers", "--header", "Git config"},
			call: func(_ *testing.T, u UI) result { return pick(u.Write("Git config")) },
		},
		{
			name: "write empty", input: unset, write: "",
			args: []string{"write", "--char-limit", "0", "--height", "15", "--show-line-numbers", "--header", "Git config"},
			call: func(_ *testing.T, u UI) result { return pick(u.Write("Git config")) },
		},
		{
			name: "write ESC", input: unset, write: "ESC",
			args: []string{"write", "--char-limit", "0", "--height", "15", "--show-line-numbers", "--header", "Git config"},
			call: func(_ *testing.T, u UI) result { return pick(u.Write("Git config")) },
		},
		{
			name: "write unset", input: unset, write: unset,
			args: []string{"write", "--char-limit", "0", "--height", "15", "--show-line-numbers", "--header", "Git config"},
			call: func(_ *testing.T, u UI) result { return pick(u.Write("Git config")) },
		},
		{
			name: "style on stdout",
			args: []string{"style", "--foreground", "2", "--bold", "first", "last line"},
			call: func(t *testing.T, u UI) result {
				return printed(capture(t, &os.Stdout, func() { u.Print(Style{Fg(2), Bold}, "first", "last line") }))
			},
		},
		{
			name: "style on stderr",
			args: []string{"style", "--border", "rounded", "--padding", "1 2", "only"},
			call: func(t *testing.T, u UI) result {
				return printed(capture(t, &os.Stderr, func() { u.Eprint(Style{Border("rounded"), Padding(1, 2)}, "only") }))
			},
		},
		{
			name: "style without text",
			args: []string{"style", "--bold"},
			call: func(t *testing.T, u UI) result {
				return printed(capture(t, &os.Stdout, func() { u.Print(Style{Bold}) }))
			},
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			dir := t.TempDir()
			setup := func(name string) {
				t.Setenv("SMOKE_LOG", filepath.Join(dir, name+".log"))
				t.Setenv("SMOKE_CHOICES", filepath.Join(dir, name+".choices"))
				t.Setenv("SMOKE_CONFIRMS", filepath.Join(dir, name+".confirms"))
				write(t, os.Getenv("SMOKE_CHOICES"), tc.choices)
				write(t, os.Getenv("SMOKE_CONFIRMS"), tc.confirms)
				for k, v := range map[string]string{"SMOKE_INPUT": tc.input, "SMOKE_WRITE": tc.write} {
					t.Setenv(k, v) // restores the variable after the test
					if v == unset {
						os.Unsetenv(k)
					}
				}
			}

			setup("bash")
			cmd := exec.Command("bash", append([]string{gum}, tc.args...)...)
			out, err := cmd.Output()
			var exit *exec.ExitError
			if err != nil && !errors.As(err, &exit) {
				t.Fatal(err)
			}
			want := result{strings.TrimRight(string(out), "\n"), err == nil}

			setup("go")
			got := tc.call(t, New())

			if got != want {
				t.Errorf("got %+v, the fake gum gave %+v", got, want)
			}
			if g, w := read(t, filepath.Join(dir, "go.log")), read(t, filepath.Join(dir, "bash.log")); g != w || w == "" {
				t.Errorf("logged %q, the fake gum logged %q", g, w)
			}
		})
	}
}

func pick(text string, ok bool) result { return result{text, ok} }

// confirm checks that the scripted UI never cancels, because the fake gum could not tell a cancel from a "No".
func confirm(t *testing.T, u UI, prompt string, defaultNo bool) result {
	yes, cancelled := u.Confirm(prompt, defaultNo)
	if cancelled {
		t.Error("Confirm cancelled")
	}
	return result{"", yes}
}

func printed(out string) result { return result{strings.TrimRight(out, "\n"), true} }

func write(t *testing.T, path, text string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(text), 0o644); err != nil {
		t.Fatal(err)
	}
}

func read(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}
