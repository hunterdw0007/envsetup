// Package ui draws envsetup's menus, questions and messages.
//
// The bash version called gum for each of these.
// Each method here matches one gum call, with the same flags in the same order.
// So the scripted UI for the tests can log the same lines that the fake gum logged.
package ui

import (
	"os"
	"strconv"
	"strings"
)

// Opt is one flag of `gum style`, such as --foreground 2 or --bold.
type Opt struct {
	flags []string
	fg    int
	bold  bool
	// border is "normal" or "rounded".
	border string
	// padding is "<vertical> <horizontal>".
	padding [2]int
}

// Style is a list of flags, in the order that the bash version passed them to gum.
type Style []Opt

// Fg sets the color, as an ANSI color number from 0 to 15.
func Fg(n int) Opt { return Opt{flags: []string{"--foreground", strconv.Itoa(n)}, fg: n} }

// Bold makes the text bold.
var Bold = Opt{flags: []string{"--bold"}, bold: true}

// Border draws a "normal" or "rounded" border around the text.
func Border(kind string) Opt { return Opt{flags: []string{"--border", kind}, border: kind} }

// Padding adds space inside the border, as "<vertical> <horizontal>".
func Padding(v, h int) Opt {
	return Opt{flags: []string{"--padding", strconv.Itoa(v) + " " + strconv.Itoa(h)}, padding: [2]int{v, h}}
}

func (s Style) flags() []string {
	var out []string
	for _, o := range s {
		out = append(out, o.flags...)
	}
	return out
}

// UI is what the menu and the actions use to talk to the user.
type UI interface {
	// Print shows a styled message on stdout, like `gum style`.
	Print(s Style, lines ...string)
	// Eprint shows a styled message on stderr, like `gum style ... >&2`.
	Eprint(s Style, lines ...string)
	// Choose shows a list and returns the picked item, like `gum choose`.
	// header may be empty.
	// ok is false when the user cancels (Esc or Ctrl-C).
	Choose(header string, options ...string) (choice string, ok bool)
	// Confirm asks a yes or no question, like `gum confirm`.
	// defaultNo starts on "No", like --default=false.
	// cancelled is true for Esc or Ctrl-C, which gum told apart from a clear "No" by its exit code.
	Confirm(prompt string, defaultNo bool) (yes, cancelled bool)
	// Input asks for one line, like `gum input --placeholder <placeholder> [--header <header>]`.
	Input(placeholder, header string) (text string, ok bool)
	// Write asks for many lines, like `gum write`.
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
