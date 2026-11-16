package ui

import (
	"fmt"
	"os"
	"strings"
	"syscall"
)

// script answers like the fake gum in tests/gum.sh did.
// It reads the answers to choose from $SMOKE_CHOICES, one per line.
// "ESC", or no answer left, cancels.
// "SIGINT" or "SIGTERM" sends that signal to the process group, like Ctrl-C or a kill.
// It reads the answers to confirm from $SMOKE_CONFIRMS.
// Only "yes" accepts, and no answer left declines.
// $SMOKE_INPUT and $SMOKE_WRITE answer input and write.
// It logs each call to $SMOKE_LOG as "gum <args>", the line that the fake gum wrote.
// Print shows only the last line, as the fake gum did.
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

func (s script) Print(st Style, lines ...string) {
	s.log([]string{"style"}, st.flags(), lines)
	if len(lines) > 0 {
		fmt.Println(lines[len(lines)-1])
	}
}

func (s script) Eprint(st Style, lines ...string) {
	s.log([]string{"style"}, st.flags(), lines)
	if len(lines) > 0 {
		fmt.Println(lines[len(lines)-1]) // the fake gum wrote to stdout, and bash sent stdout to stderr
	}
}

func (s script) Choose(header string, options ...string) (string, bool) {
	args := []string{"choose"}
	if header != "" {
		args = append(args, "--header", header)
	}
	s.log(args, options)
	answer := pop(os.Getenv("SMOKE_CHOICES"))
	if answer == "" || answer == "ESC" {
		return "", false
	}
	if sig, ok := strings.CutPrefix(answer, "SIG"); ok {
		n := map[string]syscall.Signal{"INT": syscall.SIGINT, "TERM": syscall.SIGTERM, "HUP": syscall.SIGHUP}[sig]
		_ = syscall.Kill(0, n)
		select {} // the signal handler ends the process
	}
	return answer, true
}

func (s script) Confirm(prompt string, defaultNo bool) (bool, bool) {
	args := []string{"confirm"}
	if defaultNo {
		args = append(args, "--default=false")
	}
	s.log(args, []string{prompt})
	return pop(os.Getenv("SMOKE_CONFIRMS")) == "yes", false
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
		return v, true
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
