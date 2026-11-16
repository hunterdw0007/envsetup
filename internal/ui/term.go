package ui

import (
	"errors"
	"fmt"
	"io"
	"os"
	"strings"

	"charm.land/huh/v2"
	"charm.land/lipgloss/v2"
)

// term draws the menus with huh, which runs on BubbleTea.
// It draws the messages with lipgloss.
// gum uses the same libraries, so the screen looks close to the bash version.
type term struct{}

func newTerm() UI { return term{} }

func (s Style) lipgloss() lipgloss.Style {
	st := lipgloss.NewStyle()
	for _, o := range s {
		switch {
		case o.flags[0] == "--foreground":
			st = st.Foreground(lipgloss.ANSIColor(o.fg))
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

func (term) print(w io.Writer, s Style, lines []string) {
	// gum style puts each argument on its own line.
	lipgloss.Fprintln(w, s.lipgloss().Render(strings.Join(lines, "\n")))
}

func (t term) Print(s Style, lines ...string)  { t.print(os.Stdout, s, lines) }
func (t term) Eprint(s Style, lines ...string) { t.print(os.Stderr, s, lines) }

// run shows a form on the terminal.
// The bash version drew gum on stderr, so stdout stays free for the results.
func run(field huh.Field) error {
	return huh.NewForm(huh.NewGroup(field)).WithShowHelp(true).WithOutput(os.Stderr).Run()
}

func (term) Choose(header string, options ...string) (string, bool) {
	var choice string
	opts := make([]huh.Option[string], len(options))
	for i, o := range options {
		opts[i] = huh.NewOption(o, o)
	}
	sel := huh.NewSelect[string]().Options(opts...).Value(&choice)
	if header != "" {
		sel = sel.Title(header)
	}
	if err := run(sel); err != nil {
		return "", false
	}
	return choice, true
}

func (term) Confirm(prompt string, defaultNo bool) (bool, bool) {
	yes := !defaultNo
	err := run(huh.NewConfirm().Title(prompt).Affirmative("Yes").Negative("No").Value(&yes))
	if errors.Is(err, huh.ErrUserAborted) {
		return false, true
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return false, true
	}
	return yes, false
}

func (term) Input(placeholder, header string) (string, bool) {
	var text string
	in := huh.NewInput().Placeholder(placeholder).Value(&text)
	if header != "" {
		in = in.Title(header)
	}
	if err := run(in); err != nil {
		return "", false
	}
	return text, true
}

func (term) Write(header string) (string, bool) {
	var text string
	if err := run(huh.NewText().Title(header).CharLimit(0).Lines(15).ShowLineNumbers(true).Value(&text)); err != nil {
		return "", false
	}
	return strings.TrimRight(text, "\n"), true
}
