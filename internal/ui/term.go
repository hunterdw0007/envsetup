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

// term draws the menus with huh, which runs on BubbleTea.
// It draws the messages with lipgloss.
// gum uses the same libraries, so the screen looks close to the bash version.
type term struct {
	// in feeds the keys to the forms.
	// When in is nil, BubbleTea reads stdin, or /dev/tty when stdin is not a terminal.
	in io.Reader
	// out is where the forms draw.
	out io.Writer
}

// newTerm draws the forms on stderr, as gum did.
// So the forms still show when the caller reads stdout.
func newTerm() UI { return term{out: os.Stderr} }

func (s Style) lipgloss() lipgloss.Style {
	st := lipgloss.NewStyle()
	for _, o := range s {
		switch {
		case o.flags[0] == "--foreground":
			// gum parses the flag's text the same way, so 0-15 become the basic ANSI colors.
			st = st.Foreground(lipgloss.Color(o.flags[1]))
		case o.bold:
			st = st.Bold(true)
		case o.border == "normal":
			st = st.Border(lipgloss.NormalBorder())
		case o.border == "rounded":
			st = st.Border(lipgloss.RoundedBorder())
		case o.flags[0] == "--padding":
			st = st.Padding(o.padding[0], o.padding[1])
		}
	}
	return st
}

// print writes one styled message.
// lipgloss drops the colors when NO_COLOR is set or w is not a terminal, as gum did.
func (term) print(w io.Writer, s Style, lines []string) {
	// gum style puts each argument on its own line.
	_, _ = lipgloss.Fprintln(w, s.lipgloss().Render(strings.Join(lines, "\n")))
}

func (t term) Print(s Style, lines ...string)  { t.print(os.Stdout, s, lines) }
func (t term) Eprint(s Style, lines ...string) { t.print(os.Stderr, s, lines) }

// keyMap returns huh's keys with the cancel keys of gum.
func keyMap() *huh.KeyMap {
	km := huh.NewDefaultKeyMap()
	// huh cancels only on ctrl+c, and gum also cancels on esc.
	km.Quit.SetKeys("esc", "ctrl+c")
	// gum choose has no filter.
	// The filter also uses esc, so it would clash with the cancel key.
	// A binding without keys stays off, even when huh turns it on again.
	km.Select.Filter.SetKeys()
	km.Text.Submit.SetHelp("enter", "save")
	return km
}

// run shows one field and waits for the answer.
// It returns false when the user cancels with esc or ctrl+c.
func (t term) run(field huh.Field) bool {
	f := huh.NewForm(huh.NewGroup(field)).
		// BubbleTea uses this size only when out is not a terminal.
		// Without it, huh gets a width of 0, and an input with a placeholder panics.
		// WithProgramOptions replaces all options, so it comes before WithOutput and WithInput.
		WithProgramOptions(tea.WithWindowSize(80, 24)).
		WithKeyMap(keyMap()).WithShowHelp(true).WithOutput(t.out).
		// gum never asks in plain text, and huh v2.0.3 panics there on some input.
		// huh would switch to it for TERM=dumb.
		WithAccessible(false)
	if t.in != nil {
		f = f.WithInput(t.in)
	}
	err := f.Run()
	if err != nil && !errors.Is(err, huh.ErrUserAborted) {
		fmt.Fprintln(os.Stderr, err)
	}
	return err == nil
}

func (t term) Choose(header string, options ...string) (string, bool) {
	var choice string
	sel := huh.NewSelect[string]().Options(huh.NewOptions(options...)...).Value(&choice)
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
	return strings.TrimRight(text, "\n"), true // $(gum write) dropped the trailing newlines
}
