package setup

// This file moves dotfiles out of $HOME into the XDG base folders.
// It uses xdg-ninja's notes on each program (https://github.com/b3nj5m1n/xdg-ninja).
// Those notes are text for people, so envsetup applies only two simple kinds of note:
//   - exactly one `export VAR="$XDG_*_HOME"/path` and nothing else: move and export
//   - the program already reads the XDG path, and the note names it: move only
//
// envsetup leaves a dotfile in place and lists it in these cases:
//   - the note mentions a version or extra steps
//   - the move clashes with something
//   - your startup files mention the dotfile
//
// envsetup records every move, so uninstall can move it back.
// The notes are downloaded data.
// envsetup only matches them against strict patterns and never runs them.

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

// The patterns of lib/xdg.sh in v1.0.0.
// Each uses POSIX rules (leftmost-longest), like bash's =~.
const (
	xdgVarRE     = `\$\{?XDG_(CONFIG|DATA|STATE|CACHE)_HOME\}?`
	xdgPathRE    = `((/[A-Za-z0-9._-]+)+)`
	xdgAnotherRE = `move the (file|directory|folder) to _`
)

var (
	xdgCaveat   = regexp.MustCompilePOSIX(`version|since|commit|>=|<=`)
	xdgExport   = regexp.MustCompilePOSIX(`^export ([A-Z_][A-Z0-9_]*)="?` + xdgVarRE + `"?` + xdgPathRE + `"?$`)
	xdgMove     = regexp.MustCompilePOSIX(xdgAnotherRE + xdgVarRE + xdgPathRE + `_`)
	xdgAnother  = regexp.MustCompilePOSIX(xdgAnotherRE)
	xdgBadVar   = regexp.MustCompilePOSIX(`^(BASH_ENV|ENV|LD_.*|DYLD_.*|.*_COMMAND)$`)
	xdgNonBlank = regexp.MustCompilePOSIX(`[^[:space:]]`)
	xdgHomePath = regexp.MustCompilePOSIX(`^\$HOME/([A-Za-z0-9._-]+)$`)
)

// envsetup never moves these files and variables by itself.
// A shell or envsetup reads the files before any exports load.
// More than one program, or a running agent, depends on the variables.
const (
	xdgKeepFiles = " .bashrc .bash_profile .bash_login .profile .zshrc .zshenv .zprofile .zlogin .gitconfig "
	xdgKeepVars  = " HISTFILE ZDOTDIR GNUPGHOME "
)

// xdgTarget returns the new path and the variable for a note that envsetup can apply (envsetup::xdg_target).
// The variable is empty when the note asks only for a move.
// ok is false for any other note.
func xdgTarget(help string) (target, variable string, ok bool) {
	if xdgCaveat.MatchString(strings.ToLower(help)) {
		return "", "", false
	}
	var code []string
	fenced := false
	for _, line := range strings.Split(help, "\n") {
		if strings.HasPrefix(line, "```") {
			fenced = !fenced
		} else if fenced && xdgNonBlank.MatchString(line) {
			code = append(code, line)
		}
	}

	var base, sub string
	if m := xdgExport.FindStringSubmatch(firstOf(code)); len(code) == 1 && m != nil {
		variable, base, sub = m[1], m[2], m[3]
	} else if loc := xdgMove.FindStringSubmatchIndex(help); len(code) == 0 && loc != nil {
		base, sub = help[loc[4]:loc[5]], help[loc[6]:loc[7]]
		// A second "move ... to" means more than one target, so the note is not simple.
		if xdgAnother.MatchString(help[loc[1]:]) {
			return "", "", false
		}
	} else {
		return "", "", false
	}
	// Reject a path that leads out of the XDG folder.
	// Also reject a variable that makes the shell or the program loader run the file.
	// shortcut: this checks only known names; the list that you confirm shows each export.
	if strings.Contains(sub+"/", "/../") || xdgBadVar.MatchString(variable) {
		return "", "", false
	}
	home := os.Getenv("HOME")
	dir := map[string]string{
		"CONFIG": envOr("XDG_CONFIG_HOME", home+"/.config"),
		"DATA":   envOr("XDG_DATA_HOME", home+"/.local/share"),
		"STATE":  envOr("XDG_STATE_HOME", home+"/.local/state"),
		"CACHE":  envOr("XDG_CACHE_HOME", home+"/.cache"),
	}[base]
	return dir + sub, variable, true
}

func firstOf(list []string) string {
	if len(list) == 0 {
		return ""
	}
	return list[0]
}

// envOr is ${name:-def}.
func envOr(name, def string) string {
	if v := os.Getenv(name); v != "" {
		return v
	}
	return def
}

// xdgItem is one dotfile of the plan: a move, or a skip with its reason.
type xdgItem struct {
	name, old, new, variable, reason string
}

// xdgCache is where envsetup keeps xdg-ninja's notes.
func (s *Setup) xdgCache() string { return s.CacheDir() + "/xdg-ninja" }

// xdgMoves is the list of moves that uninstall undoes.
func (s *Setup) xdgMoves() string { return s.State + "/xdg-moves" }

// xdgEnv is the exports file that every shell loads (shell/init.sh).
func (s *Setup) xdgEnv() string { return s.State + "/xdg.sh" }

// unTSV undoes the escapes that jq's @tsv adds, like printf %b did.
var unTSV = strings.NewReplacer(`\\`, `\`, `\t`, "\t", `\n`, "\n", `\r`, "\r")

// xdgPlan sorts each dotfile in $HOME that a note names into skips and moves (envsetup::xdg_plan).
func (s *Setup) xdgPlan() (skips, moves []xdgItem) {
	var rcs []string
	for _, rc := range []string{".bashrc", ".bash_profile", ".profile", ".zshrc", ".zprofile", ".zshenv"} {
		if isFile(s.Home + "/" + rc) {
			rcs = append(rcs, s.Home+"/"+rc)
		}
	}
	files, _ := filepath.Glob(s.xdgCache() + "/programs/*.json")
	if files == nil {
		files = []string{s.xdgCache() + "/programs/*.json"} // like bash, jq gets the pattern and reports it
	}
	c := exec.Command("jq", append([]string{"-r", `.name as $n | .files[] | select(.movable) | [$n, .path, .help] | @tsv`}, files...)...)
	c.Stderr = os.Stderr
	out, _ := c.Output()

	var planned []xdgItem
	varCount := map[string]int{}
	for _, line := range splitLines(string(out)) {
		// read with IFS=$'\t' drops empty fields, and the last one keeps the rest of the line.
		f := strings.FieldsFunc(line, func(r rune) bool { return r == '\t' })
		for len(f) < 3 {
			f = append(f, "")
		}
		name, path, help := f[0], f[1], strings.Join(f[2:], "\t")
		m := xdgHomePath.FindStringSubmatch(path)
		if m == nil {
			continue
		}
		old := s.Home + "/" + m[1]
		if !exists(old) {
			continue
		}
		help = unTSV.Replace(help)
		skip := func(reason string) { skips = append(skips, xdgItem{name: name, old: old, reason: reason}) }
		fi, _ := os.Lstat(old)
		target, variable, ok := xdgTarget(help)
		_, set := os.LookupEnv(variable)
		switch {
		case fi.Mode()&os.ModeSymlink != 0:
			skip("it is a symlink, so something else may manage it")
		case strings.Contains(xdgKeepFiles, " "+m[1]+" "):
			skip("a shell or envsetup reads it at startup")
		case !ok:
			skip("needs manual steps (see xdg-ninja)")
		case variable != "" && strings.Contains(xdgKeepVars, " "+variable+" "):
			skip("$" + variable + " is shared with other programs")
		case variable != "" && set:
			skip("$" + variable + " is already set")
		case exists(target):
			skip(target + " already exists")
		default:
			if refs := referencedFrom(rcs, m[1], old); refs != "" {
				skip("referenced from " + refs)
				continue
			}
			planned = append(planned, xdgItem{name: name, old: old, new: target, variable: variable})
			if variable != "" {
				varCount[variable]++
			}
		}
	}
	for _, it := range planned {
		if it.variable != "" && varCount[it.variable] > 1 {
			skips = append(skips, xdgItem{name: it.name, old: it.old, reason: "more than one program uses $" + it.variable})
		} else {
			moves = append(moves, it)
		}
	}
	return skips, moves
}

// referencedFrom lists the startup files that mention the dotfile, like grep -lF, joined by ", ".
func referencedFrom(rcs []string, base, old string) string {
	needles := []string{"~/" + base, "$HOME/" + base, "${HOME}/" + base, old}
	var found []string
	for _, rc := range rcs {
		data, err := os.ReadFile(rc)
		if err != nil {
			continue
		}
		for _, n := range needles {
			if strings.Contains(string(data), n) {
				found = append(found, rc)
				break
			}
		}
	}
	return strings.Join(found, ", ")
}

// xdgFetch clones xdg-ninja's notes into the cache, or updates them (envsetup::xdg_fetch).
// Without a network, it uses the copy that is already there.
// It returns false when there are no notes to use.
func (s *Setup) xdgFetch() bool {
	cache := s.xdgCache()
	switch {
	case isDir(cache + "/.git"):
		if s.DryRun {
			return true
		}
		if s.Run("git", "-C", cache, "pull", "-q", "--ff-only") != nil {
			s.Warn("Couldn't update xdg-ninja's notes. Using the copy from last time.")
		}
	case s.DryRun:
		s.Would("download xdg-ninja's notes into " + cache + ", then look for dotfiles to move")
		return false
	default:
		url := envOr("ENVSETUP_XDG_NINJA_URL", "https://github.com/b3nj5m1n/xdg-ninja")
		_ = os.MkdirAll(s.CacheDir(), 0o777)
		if s.Run("git", "clone", "-q", "--depth", "1", url, cache) != nil {
			s.Fail("Couldn't download xdg-ninja's notes from " + url)
			return false
		}
	}
	return true
}

// xdgWriteEnv writes the exports again from the list of moves (envsetup::xdg_write_env).
func (s *Setup) xdgWriteEnv() error {
	data, err := os.ReadFile(s.xdgMoves())
	if err != nil {
		return err
	}
	var b strings.Builder
	b.WriteString("# envsetup generates this file from " + s.xdgMoves() + ". It overwrites any edits.\n")
	for _, line := range splitLines(string(data)) {
		if _, new, variable := splitMove(line); variable != "" {
			b.WriteString("export " + variable + "=" + Quote(new) + "\n")
		}
	}
	return os.WriteFile(s.xdgEnv(), []byte(b.String()), 0o666)
}

// splitMove splits a line of the list of moves, like read -r old new var with IFS=$'\t'.
func splitMove(line string) (old, new, variable string) {
	f := strings.FieldsFunc(line, func(r rune) bool { return r == '\t' })
	for len(f) < 3 {
		f = append(f, "")
	}
	return f[0], f[1], strings.Join(f[2:], "\t")
}

// tilde writes a path under $HOME with ~, like ${p/#$HOME/\~}.
func (s *Setup) tilde(p string) string {
	if rest, ok := strings.CutPrefix(p, s.Home); ok {
		return "~" + rest
	}
	return p
}

// XDGTidy moves dotfiles into the XDG folders (envsetup::xdg_tidy).
func (s *Setup) XDGTidy() error {
	if !HasCmd("jq") || !HasCmd("git") {
		s.Warn("Moving dotfiles needs jq and git. packages/common.txt includes both. Skipping this step.")
		return nil
	}
	if !s.xdgFetch() {
		return nil
	}
	skips, moves := s.xdgPlan()
	for _, it := range skips {
		s.Warn("  leaving " + s.tilde(it.old) + " (" + it.name + "): " + strings.ReplaceAll(it.reason, s.Home, "~"))
	}
	if len(moves) == 0 {
		s.Say("No dotfiles to move.")
		return nil
	}
	for _, it := range moves {
		line := "move " + s.tilde(it.old) + " to " + s.tilde(it.new)
		if it.variable != "" {
			line += " and export " + it.variable
		}
		if s.DryRun {
			s.Would(line)
		} else {
			s.Say("  " + line)
		}
	}
	if s.DryRun {
		return nil
	}
	if yes, _ := s.UI.Confirm("Move these "+strconv.Itoa(len(moves))+" dotfiles? Uninstall moves them back.", false); !yes {
		return nil
	}

	_ = os.MkdirAll(filepath.Dir(s.xdgMoves()), 0o777)
	list, err := os.OpenFile(s.xdgMoves(), os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o666)
	if err != nil {
		return err
	}
	defer list.Close()
	failed := false
	for _, it := range moves {
		if os.MkdirAll(filepath.Dir(it.new), 0o777) == nil && s.Run("mv", "-n", it.old, it.new) == nil && !statOK(it.old) {
			// Uninstall moves a dotfile back only from this list, so a failed write ends the step, as set -e did.
			if _, err := fmt.Fprintf(list, "%s\t%s\t%s\n", it.old, it.new, it.variable); err != nil {
				list.Close()
				return err
			}
		} else {
			s.Fail("Couldn't move " + it.old)
			failed = true
		}
	}
	if err := s.xdgWriteEnv(); err != nil {
		return err
	}
	s.Success("Moved. New shells get the exports. Programs that are already running still use the old paths.")
	if failed {
		return ErrFailed
	}
	return nil
}

// statOK is [[ -e p ]]: it follows links.
func statOK(p string) bool {
	_, err := os.Stat(p)
	return err == nil
}

// xdgRestore moves every dotfile back, newest move first (envsetup::xdg_restore).
// Then it deletes the exports, the list of moves and the saved notes.
// A move that it cannot undo stays in the list, with its export.
// So a later uninstall can try again.
func (s *Setup) xdgRestore() error {
	var kept []string
	files := []string{s.xdgCache()}
	if isFile(s.xdgMoves()) {
		data, _ := os.ReadFile(s.xdgMoves())
		lines := splitLines(string(data))
		for i := len(lines) - 1; i >= 0; i-- {
			old, new, _ := splitMove(lines[i])
			if !statOK(new) {
				continue
			}
			var reason string
			switch {
			case statOK(old):
				reason = old + " exists again"
			case s.DryRun:
				s.Would("move " + new + " back to " + old)
				continue
			case s.Run("mv", "-n", new, old) == nil && !statOK(new):
				rmdir(filepath.Dir(new), false) // the folder that the move created, if it is empty now
				continue
			default:
				reason = "couldn't move it"
			}
			s.Fail("Leaving " + new + " where it is: " + reason + ". Fix that, then uninstall again.")
			kept = append([]string{lines[i]}, kept...)
		}
	}
	failed := false
	if len(kept) == 0 {
		files = append(files, s.xdgMoves(), s.xdgEnv())
	} else if !s.DryRun {
		if err := os.WriteFile(s.xdgMoves(), []byte(strings.Join(kept, "\n")+"\n"), 0o666); err == nil {
			_ = s.xdgWriteEnv()
		}
		failed = true
	}
	for _, f := range files {
		if !statOK(f) {
			continue
		}
		if s.DryRun {
			s.Would("delete " + f)
		} else {
			_ = os.RemoveAll(f)
		}
	}
	if !s.DryRun {
		rmdir(s.CacheDir(), false)
	}
	if failed {
		return ErrFailed
	}
	return nil
}
