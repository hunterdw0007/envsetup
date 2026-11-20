package ui

import (
	"errors"
	"fmt"
	"io"
	"os"
	"strings"

	tea "charm.land/bubbletea/v2"
	"charm.land/huh/v2"
	"charm.land/lipgloss/v2"
)

// term draws the menus with huh, which runs on BubbleTea, and the messages with lipgloss.
type term struct {
	// in feeds the keys to the forms.
	// When in is nil, BubbleTea reads stdin, or /dev/tty when stdin is not a terminal.
	in io.Reader
	// out is where the forms draw.
	out io.Writer
}

// newTerm draws the forms on stderr.
// So the forms still show when stdout goes to a pipe or a file.
func newTerm() UI { return term{out: os.Stderr} }

// The colors of huh's Charm theme, so the messages match the forms.
// lipgloss picks the nearest color on terminals with fewer colors.
var (
	indigo  = lipgloss.Color("#7571F9")
	fuchsia = lipgloss.Color("#F780E2")
	green   = lipgloss.Color("#02BF87")
	red     = lipgloss.Color("#ED567A")
	amber   = lipgloss.Color("#F5A623")
	grey    = lipgloss.Color("#8A8A8A")
)

// theme gives each kind of message its look.
var theme = map[Kind]lipgloss.Style{
	Plain:   lipgloss.NewStyle(),
	Success: lipgloss.NewStyle().Foreground(green),
	Warn:    lipgloss.NewStyle().Foreground(amber),
	Fail:    lipgloss.NewStyle().Foreground(red).Bold(true),
	Note:    lipgloss.NewStyle().Foreground(grey).Italic(true),
	Ask:     lipgloss.NewStyle().Foreground(indigo).Bold(true),
	Step:    lipgloss.NewStyle().Foreground(fuchsia).Bold(true),
	Heading: lipgloss.NewStyle().Bold(true),
	Title: lipgloss.NewStyle().Bold(true).Foreground(fuchsia).
		Border(lipgloss.RoundedBorder()).BorderForeground(indigo).Padding(0, 2),
	Welcome: lipgloss.NewStyle().Border(lipgloss.RoundedBorder()).BorderForeground(grey).Padding(0, 1),
}

// print writes one message, one line for each item of lines.
// lipgloss drops the colors when NO_COLOR is set or w is not a terminal.
func (term) print(w io.Writer, k Kind, lines []string) {
	_, _ = lipgloss.Fprintln(w, theme[k].Render(strings.Join(lines, "\n")))
}

func (t term) Print(k Kind, lines ...string)  { t.print(os.Stdout, k, lines) }
func (t term) Eprint(k Kind, lines ...string) { t.print(os.Stderr, k, lines) }

// keyMap returns huh's keys, with esc as a second key to cancel.
func keyMap() *huh.KeyMap {
	km := huh.NewDefaultKeyMap()
	// Every question can be cancelled, and esc is the key that people try first.
	km.Quit.SetKeys("esc", "ctrl+c")
	// The filter also uses esc, so it would clash with the cancel key.
	// A binding without keys stays off, even when huh turns it on again.
	km.Select.Filter.SetKeys()
	km.Text.Submit.SetHelp("enter", "save")
	return km
}

// run shows one field and waits for the answer.
// It returns false when the user cancels with esc or ctrl+c.
func (t term) run(field huh.Field) (ok bool) {
	// With TERM=dumb, huh asks in plain text, for screen readers (accessible mode).
	// There, huh v2.0.3 panics when the input ends (Ctrl-D), so that counts as a cancel.
	// shortcut: this recovers any panic of the form; drop it once huh handles the end of input.
	defer func() {
		if recover() != nil {
			ok = false
		}
	}()
	f := huh.NewForm(huh.NewGroup(field)).
		// BubbleTea uses this size only when out is not a terminal.
		// Without it, huh gets a width of 0, and an input with a placeholder panics.
		// WithProgramOptions replaces all options, so it comes before WithOutput and WithInput.
		WithProgramOptions(tea.WithWindowSize(80, 24)).
		WithKeyMap(keyMap()).WithShowHelp(true).WithOutput(t.out)
	if t.in != nil {
		f = f.WithInput(t.in)
	}
	err := f.Run()
	if err != nil && !errors.Is(err, huh.ErrUserAborted) {
		fmt.Fprintln(os.Stderr, err)
	}
	return err == nil
}

// desc is the look of an option's description in a list.
var desc = lipgloss.NewStyle().Foreground(grey)

func (t term) Choose(header string, options ...Option) (string, bool) {
	var choice string
	opts := make([]huh.Option[string], len(options))
	for i, o := range options {
		key := o.label()
		if o.Desc != "" {
			key += "  " + desc.Render(o.Desc)
		}
		opts[i] = huh.NewOption(key, o.Value)
	}
	sel := huh.NewSelect[string]().Options(opts...).Value(&choice)
	if header != "" {
		sel = sel.Title(header)
	}
	if !t.run(sel) {
		return "", false
	}
	return choice, true
}

func (t term) Confirm(prompt string, defaultNo bool) (bool, bool) {
	yes := !defaultNo
	if !t.run(huh.NewConfirm().Title(prompt).Affirmative("Yes").Negative("No").Value(&yes)) {
		return false, true
	}
	return yes, false
}

func (t term) Input(placeholder, header string) (string, bool) {
	var text string
	in := huh.NewInput().Placeholder(placeholder).Value(&text)
	if header != "" {
		in = in.Title(header)
	}
	if !t.run(in) {
		return "", false
	}
	return text, true
}

func (t term) Write(header string) (string, bool) {
	var text string
	// The help line shows the keys to save and to add a line, but not the cancel key.
	field := huh.NewText().Title(header).Description("Press esc to cancel.").
		CharLimit(0).Lines(15).ShowLineNumbers(true).Value(&text)
	if !t.run(field) {
		return "", false
	}
	return strings.TrimRight(text, "\n"), true
}
