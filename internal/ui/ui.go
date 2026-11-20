// Package ui draws envsetup's menus, questions and messages.
//
// Callers say what a message means (a Kind), and the terminal UI picks its look.
// The scripted UI for the tests turns each call into the line that the fake gum logged (script.go).
package ui

import (
	"os"
	"strings"
)

// Kind says what a message means.
type Kind int

// The kinds of message.
const (
	Plain   Kind = iota
	Success      // a change that worked
	Warn         // something to know, such as a skipped part
	Fail         // an error
	Note         // a dry-run note, such as "  would ..."
	Ask          // the question above a list
	Step         // a step that starts, such as "Running kubectl.sh..."
	Heading      // a heading above other output
	Title        // the banner with the release
	Welcome      // the box that a first run shows
)

// Option is one item of a list.
// Choose shows Label, or Value when Label is empty, and returns Value.
// Desc, when set, says what the item does.
type Option struct {
	Value, Label, Desc string
}

// Options makes one Option for each value.
func Options(values ...string) []Option {
	opts := make([]Option, len(values))
	for i, v := range values {
		opts[i] = Option{Value: v}
	}
	return opts
}

func (o Option) label() string {
	if o.Label != "" {
		return o.Label
	}
	return o.Value
}

// UI is what the menu and the actions use to talk to the user.
type UI interface {
	// Print shows a message on stdout, one line for each item of lines.
	Print(k Kind, lines ...string)
	// Eprint shows a message on stderr.
	Eprint(k Kind, lines ...string)
	// Choose shows a list and returns the Value of the picked item.
	// header may be empty.
	// ok is false when the user cancels (Esc or Ctrl-C).
	Choose(header string, options ...Option) (value string, ok bool)
	// Confirm asks a yes or no question.
	// defaultNo starts on "No".
	// cancelled is true for Esc or Ctrl-C, which is not the same as a clear "No".
	Confirm(prompt string, defaultNo bool) (yes, cancelled bool)
	// Input asks for one line. header may be empty.
	Input(placeholder, header string) (text string, ok bool)
	// Write asks for many lines.
	Write(header string) (text string, ok bool)
}

// New returns the scripted UI when the tests set SMOKE_CHOICES.
// Otherwise it returns the terminal UI.
func New() UI {
	if os.Getenv("SMOKE_CHOICES") != "" {
		return newScript()
	}
	return newTerm()
}

func join(parts ...[]string) string {
	var all []string
	for _, p := range parts {
		all = append(all, p...)
	}
	return strings.Join(all, " ")
}
