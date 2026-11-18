package ui

import (
	"fmt"
	"io"
	"os"
	"strings"
	"syscall"
)

// script answers like the fake gum in tests/gum.sh did.
// It is a test adapter: it turns each call into the gum call that the bash version (v1.0.0) made.
// It reads the answers to choose from $SMOKE_CHOICES, one per line.
// "ESC", or no answer left, cancels.
// "SIGINT" or "SIGTERM" sends that signal to the process group, like Ctrl-C or a kill.
// It reads the answers to confirm from $SMOKE_CONFIRMS.
// Only "yes" accepts, "ESC" cancels, and no answer left declines.
// $SMOKE_INPUT and $SMOKE_WRITE answer input and write.
// It logs each call to $SMOKE_LOG as "gum <args>", the line that the fake gum wrote.
// Print and Eprint show only the last argument, as the fake gum did.
// So the tests can compare the bash version and this one line for line.
type script struct{}

func newScript() UI { return script{} }

func (script) log(args ...[]string) {
	f, err := os.OpenFile(os.Getenv("SMOKE_LOG"), os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return
	}
	defer f.Close()
	fmt.Fprintln(f, join(append([][]string{{"gum"}}, args...)...))
}

// pop removes the first line of the file and returns it.
func pop(path string) string {
	data, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	first, rest, _ := strings.Cut(string(data), "\n")
	_ = os.WriteFile(path, []byte(rest), 0o644)
	return first
}

// gumFlags holds the `gum style` flags that the bash version used for each kind of message.
var gumFlags = map[Kind][]string{
	Success: {"--foreground", "2"},
	Warn:    {"--foreground", "3"},
	Fail:    {"--foreground", "1"},
	Note:    {"--foreground", "6"},
	Ask:     {"--foreground", "4"},
	Step:    {"--bold", "--foreground", "4"},
	Heading: {"--bold"},
	Title:   {"--border", "rounded", "--padding", "1 2", "--bold"},
	Welcome: {"--border", "normal", "--padding", "0 1"},
}

// style logs a `gum style` call and prints what the fake gum printed: its last argument.
func (s script) style(w io.Writer, k Kind, lines []string) {
	args := append(append([]string{"style"}, gumFlags[k]...), lines...)
	s.log(args)
	fmt.Fprintln(w, args[len(args)-1])
}

func (s script) Print(k Kind, lines ...string)  { s.style(os.Stdout, k, lines) }
func (s script) Eprint(k Kind, lines ...string) { s.style(os.Stderr, k, lines) }

// gumLine is the line that the bash version passed to gum choose for an option: "<value>  <description>".
func gumLine(o Option) string {
	if o.Desc != "" {
		return o.label() + "  " + o.Desc
	}
	return o.label()
}

func (s script) Choose(header string, options ...Option) (string, bool) {
	args := []string{"choose"}
	if header != "" {
		args = append(args, "--header", header)
	}
	lines := make([]string, len(options))
	for i, o := range options {
		lines[i] = gumLine(o)
	}
	s.log(args, lines)
	answer := pop(os.Getenv("SMOKE_CHOICES"))
	if answer == "" || answer == "ESC" {
		return "", false
	}
	// The fake gum's kill failed on an unknown signal, and then it printed the answer.
	if sig, ok := map[string]syscall.Signal{"SIGINT": syscall.SIGINT, "SIGTERM": syscall.SIGTERM, "SIGHUP": syscall.SIGHUP}[answer]; ok {
		_ = syscall.Kill(0, sig)
		select {} // the signal handler ends the process
	}
	return pickValue(answer, options), true
}

// pickValue finds the option that an answer names, the way the bash version read gum's answer.
// bash kept the first word of a line with a description (${choice%% *}).
// It matched a menu item with a changing label by its start, such as "Select profile"*.
// An answer that names no option comes back as it is, and the caller treats it as unknown.
func pickValue(answer string, options []Option) string {
	word, _, _ := strings.Cut(answer, " ")
	for _, o := range options {
		if answer == gumLine(o) || (o.Desc != "" && word == o.Value) {
			return o.Value
		}
	}
	for _, o := range options {
		if o.Label != "" && strings.HasPrefix(answer, o.Value) {
			return o.Value
		}
	}
	return answer
}

func (s script) Confirm(prompt string, defaultNo bool) (bool, bool) {
	args := []string{"confirm"}
	if defaultNo {
		args = append(args, "--default=false")
	}
	s.log(args, []string{prompt})
	switch pop(os.Getenv("SMOKE_CONFIRMS")) {
	case "yes":
		return true, false
	case "ESC":
		return false, true
	}
	return false, false
}

func (s script) Input(placeholder, header string) (string, bool) {
	args := []string{"input", "--placeholder", placeholder}
	if header != "" {
		args = append(args, "--header", header)
	}
	s.log(args)
	v, set := os.LookupEnv("SMOKE_INPUT")
	switch {
	case set && v == "ESC":
		return "", false
	case set:
		return strings.TrimRight(v, "\n"), true // $(gum input) dropped the trailing newlines
	case strings.Contains(strings.Join(args, " "), "@"):
		return "smoke@example.com", true
	default:
		return "Smoke Test", true
	}
}

func (s script) Write(header string) (string, bool) {
	s.log([]string{"write", "--char-limit", "0", "--height", "15", "--show-line-numbers", "--header", header})
	v, set := os.LookupEnv("SMOKE_WRITE")
	if !set || v == "ESC" {
		return "", false
	}
	return strings.TrimRight(v, "\n"), true // $(gum write) dropped the trailing newlines
}
