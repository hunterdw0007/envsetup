package setup

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// This file holds the actions that change config.sh, from lib/config.sh of the bash version.

// SyncConfigRepo gets config.sh from the user's own git repo (envsetup::sync_config_repo).
// The first run clones ENVSETUP_CONFIG_REPO into the clone folder.
// Setting ENVSETUP_CONFIG_REPO is the user's choice to clone.
// Later runs ask before they pull the clone.
// They do not need ENVSETUP_CONFIG_REPO.
// Then config.sh becomes a symlink to the config.sh in the clone.
// It asks before it replaces a config.sh of the user's own, and moves that file to config.sh.bak first.
// If the user keeps their own config.sh, later runs neither ask nor pull.
// A failed clone or pull shows a warning, and the menu still opens.
func (s *Setup) SyncConfigRepo() error {
	url := configRepoURL(os.Getenv("ENVSETUP_CONFIG_REPO"))
	repo, link := s.Clone, s.State+"/config.sh"
	switch {
	case isDir(repo + "/.git"):
		c := s.Cmd("git", "-C", repo, "remote", "get-url", "origin")
		c.Stdout, c.Stderr = nil, nil
		out, _ := c.Output()
		origin := strings.TrimRight(string(out), "\n")
		if url != "" && url != origin {
			from := origin
			if from == "" {
				from = "an unknown URL"
			}
			s.Color(3, "ENVSETUP_CONFIG_REPO is "+url+", but "+repo+" comes from "+from+". envsetup keeps using "+repo+".")
		}
		// The user kept their own config.sh, so the clone does not matter to this run.
		if exists(link) && readlink(link) != repo+"/config.sh" {
			return nil
		}
		if s.DryRun {
			s.Would("ask to pull " + repo)
		} else if yes, _ := s.UI.Confirm("Pull your config repo ("+repo+") before the menu opens?", false); yes {
			if s.Run("git", "-C", repo, "pull", "-q", "--ff-only") != nil {
				s.Color(3, "Couldn't pull "+repo+". Commit and push your edits there, or undo them. envsetup uses the config.sh that it has.")
			}
		}
	case url != "":
		if s.DryRun {
			s.Would("clone " + url + " into " + repo)
			s.Would("link " + link + " to " + repo + "/config.sh")
			return nil
		}
		if s.Run("git", "clone", "-q", "--", url, repo) != nil {
			s.Color(3, "Couldn't clone "+url+". Check ENVSETUP_CONFIG_REPO, then run setup again. The menu opens without your repo.")
			return nil
		}
		s.Color(2, "Cloned "+url+" into "+repo)
	default:
		return nil
	}

	if !isFile(repo + "/config.sh") {
		s.Color(3, repo+" has no config.sh, so envsetup links none.")
		return nil
	}
	if readlink(link) == repo+"/config.sh" {
		return nil
	}
	// Only a run that just cloned gets here with a config.sh of the user's own, so this is never a dry run.
	if exists(link) {
		// Only a clear no replaces the file. Ctrl-C keeps it.
		yes, cancelled := s.UI.Confirm("Keep your own "+link+"? No moves it to "+link+".bak and links "+repo+"/config.sh instead.", false)
		if yes || cancelled {
			return nil
		}
		if exists(link + ".bak") {
			s.Color(3, link+".bak already exists, so envsetup keeps "+link+" as it is.")
			return nil
		}
		if err := os.Rename(link, link+".bak"); err != nil {
			return err
		}
		s.Color(2, "Moved your old config.sh to "+link+".bak")
	}
	if s.DryRun {
		s.Would("link " + link + " to " + repo + "/config.sh")
		return nil
	}
	// Like ln -sfn: replace the link itself.
	if err := os.Remove(link); err != nil && !errors.Is(err, fs.ErrNotExist) {
		return err
	}
	if err := os.Symlink(repo+"/config.sh", link); err != nil {
		return err
	}
	s.Color(2, "Linked "+link+" to "+repo+"/config.sh")
	return nil
}

var shortRepo = regexp.MustCompile(`^[^/:.]+/[^/:]+$`)

// configRepoURL expands the short forms of ENVSETUP_CONFIG_REPO.
func configRepoURL(url string) string {
	if url == "" {
		return ""
	}
	// The short form "me" means github.com/me/envsetup-config.
	if !strings.Contains(url, "/") && !strings.Contains(url, ":") {
		url = "github.com/" + url + "/envsetup-config"
	}
	// The short form "me/dotfiles" means github.com/me/dotfiles.
	if shortRepo.MatchString(url) {
		url = "github.com/" + url
	}
	// A URL without a scheme, such as github.com/me/dotfiles, uses https.
	if !strings.Contains(url, ":") && !strings.HasPrefix(url, "/") {
		url = "https://" + url
	}
	return url
}

// readlink returns a link's target, or "" like $(readlink f) for a file that is no link.
func readlink(p string) string {
	t, _ := os.Readlink(p)
	return t
}

// renamed returns ENVSETUP_RENAMED from lib/config.sh, as old=new items.
// It reads the list from bash, because lib/config.sh owns it.
// It does not run config.sh.
func (s *Setup) renamed() ([]string, error) {
	c := s.Cmd("bash", "-c", `source "$ENVSETUP_ROOT/lib/common.sh" && source "$ENVSETUP_ROOT/lib/config.sh" &&
printf '%s\0' "${ENVSETUP_RENAMED[@]}"`)
	c.Stdout = nil
	out, err := c.Output()
	if err != nil {
		return nil, err
	}
	var items []string
	for _, item := range strings.Split(string(out), "\x00") {
		if item != "" {
			items = append(items, item)
		}
	}
	return items, nil
}

// MigrateConfig asks to rename the old names from ENVSETUP_RENAMED in config.sh (envsetup::migrate_config).
// It changes only whole words that match an old name.
// A dry run only describes the change.
// After a "no", load_config still reads the old names, and the next run asks again.
func (s *Setup) MigrateConfig() error {
	file := s.UserConfig
	if !isFile(file) {
		return nil
	}
	items, err := s.renamed()
	if err != nil {
		return err
	}
	data, err := os.ReadFile(file)
	if err != nil {
		return err
	}
	var found []string
	list := ""
	for _, item := range items {
		old, new, _ := strings.Cut(item, "=")
		if hasWord(string(data), old) {
			found = append(found, item)
			list += " " + old + " → " + new
		}
	}
	if len(found) == 0 {
		return nil
	}
	if s.DryRun {
		// A dry run's file is a temporary copy, so name the real file.
		s.Would("ask to rename these settings in " + s.State + "/config.sh:" + list)
		return nil
	}
	// The old names still work after a "no", so "no" is the safe default.
	if yes, _ := s.UI.Confirm("Some settings in "+file+" have a new name:"+list+". Rename them in "+file+"?", true); !yes {
		s.Color(3, "envsetup keeps "+file+" as it is and reads the old names. The next run asks again.")
		return nil
	}
	if err := writeThrough(file, renameWords(string(data), found)); err != nil {
		return err
	}
	s.Color(2, "Renamed the settings in "+file+":"+list)
	s.warnConfigRepo()
	return nil
}

// words splits text into words and the text between words, byte by byte like the C locale.
var words = regexp.MustCompile(`[A-Za-z0-9_]+|[^A-Za-z0-9_]+`)

// hasWord reports whether the name appears in the text as a whole word, like grep -qw.
func hasWord(text, name string) bool {
	for _, tok := range words.FindAllString(text, -1) {
		if tok == name {
			return true
		}
	}
	return false
}

// renameWords renames each whole word that matches an old name of the old=new items.
// It applies the items in order, so A=B and then B=C turn A into C, as the bash version did.
// A last line without a newline stays without one.
func renameWords(text string, items []string) string {
	return words.ReplaceAllStringFunc(text, func(tok string) string {
		for _, item := range items {
			if old, new, _ := strings.Cut(item, "="); tok == old {
				tok = new
			}
		}
		return tok
	})
}

// writeThrough writes the file like `printf ... >file`.
// It keeps the mode of a file that exists, and writes through a link.
func writeThrough(file, text string) error {
	f, err := os.OpenFile(file, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0o666)
	if err != nil {
		return err
	}
	if _, err := f.WriteString(text); err != nil {
		f.Close()
		return err
	}
	return f.Close()
}

// warnConfigRepo warns when config.sh links into the clone of the user's config repo (envsetup::warn_config_repo).
// A dry run edits a plain copy, so it gets no warning.
func (s *Setup) warnConfigRepo() {
	if isLink(s.UserConfig) {
		s.Color(3, "This config.sh is in your config repo. Commit and push your edits there, or a later pull fails.")
	}
}

// isLink is like [[ -L f ]].
func isLink(p string) bool {
	fi, err := os.Lstat(p)
	return err == nil && fi.Mode()&fs.ModeSymlink != 0
}

// EditConfig opens config.sh in $EDITOR (envsetup::edit_config).
// Without $EDITOR, it uses nano if the machine has it, and vi otherwise.
func (s *Setup) EditConfig() error {
	file := s.UserConfig
	// A link to a file that is gone would make the copy below write into the clone.
	if _, err := os.Stat(file); err != nil && isLink(file) {
		s.Color(3, file+" linked to a file that is gone. Edit config replaces the link with a new config.sh.")
		if err := os.Remove(file); err != nil {
			return err
		}
	}
	if !isFile(file) {
		if err := os.MkdirAll(filepath.Dir(file), 0o777); err != nil {
			return err
		}
		if err := copyFile(s.Root+"/config.example.sh", file); err != nil {
			return err
		}
	}
	s.warnConfigRepo()
	before := s.SettingsOf(file)
	args := editorArgs(os.Getenv("EDITOR"), HasCmd("nano"))
	args = append(args, file)
	if err := s.Run(args[0], args[1:]...); err != nil {
		return err
	}
	if !s.checkConfig(file, file+" has an error. Run envsetup config, or select Edit config, to fix it:", "bash") {
		return ErrFailed
	}
	s.showChanges(before, s.SettingsOf(file))
	return nil
}

// editorArgs splits $EDITOR into words, like `read -ra editor <<<"$EDITOR"`.
// read takes only the first line.
func editorArgs(editor string, nano bool) []string {
	switch {
	case editor != "":
		line, _, _ := strings.Cut(editor, "\n")
		return strings.Fields(line)
	case nano:
		return []string{"nano"}
	}
	return []string{"vi"}
}

// copyFile copies a file to a new file like cp: the new file gets the mode of the source.
func copyFile(src, dst string) error {
	fi, err := os.Stat(src)
	if err != nil {
		return err
	}
	data, err := os.ReadFile(src)
	if err != nil {
		return err
	}
	return os.WriteFile(dst, data, fi.Mode().Perm())
}

// PasteConfig saves the text that the user pastes (envsetup::paste_config).
// It asks where the text goes: the end of config.sh, or a new file in shell.d.
func (s *Setup) PasteConfig() error {
	// gum shows its own keys to save and to cancel under the box.
	text, ok := s.UI.Write("Paste your settings or shell code.")
	if !ok {
		return nil
	}
	choice, ok := s.UI.Choose("Where does the text go?",
		"settings  the end of config.sh",
		"shell  a new file in shell.d, next to config.sh")
	if !ok {
		return nil
	}
	if first, _, _ := strings.Cut(choice, " "); first == "shell" {
		return s.addShellFile(text)
	}
	return s.addConfig(text)
}

// cleanText drops the trailing newlines and then each \r, like ${text//$'\r'/} after text=$(<file).
// A paste from Windows (WSL) has \r at the end of each line, and bash reads it as part of the command.
func cleanText(text string) string {
	return strings.ReplaceAll(strings.TrimRight(text, "\n"), "\r", "")
}

// blank reports whether the text holds only spaces, like [[ -z "${text//[[:space:]]/}" ]].
func blank(text string) bool { return strings.Trim(text, " \t\n\v\f\r") == "" }

var shellFileName = regexp.MustCompile(`^[[:alnum:]_][[:alnum:]._-]*$`)

// addShellFile saves the text as a new file in shell.d (envsetup::add_shell_file).
// It asks for the name.
// It saves nothing if a shell that loads the file finds a syntax error, or if the file stops before its end.
// It asks before it replaces a file, and the default answer keeps the old file.
// A dry run checks only the syntax, because the other check runs the text.
func (s *Setup) addShellFile(text string) error {
	text = cleanText(text)
	if blank(text) {
		s.Color(3, "The text is empty, so envsetup saved nothing.")
		return nil
	}
	add := s.Tmp + "/add.sh"
	if err := os.WriteFile(add, []byte(text+"\n"), 0o666); err != nil {
		return err
	}
	name, ok := s.UI.Input("aliases.sh", "File name. New bash and zsh shells load .sh files. Only bash loads .bash, and only zsh loads .zsh.")
	if !ok || name == "" { // an empty name is a cancel
		return nil
	}
	// The action shows its own message, so a bad name is not a failed step.
	if !shellFileName.MatchString(name) {
		s.Color(3, `"`+name+`" is not a file name, so envsetup saved nothing. Use letters, digits, dots, dashes and underscores.`)
		return nil
	}
	// shell/init.sh skips a file without one of these endings.
	if !strings.HasSuffix(name, ".sh") && !strings.HasSuffix(name, ".bash") && !strings.HasSuffix(name, ".zsh") {
		name += ".sh"
	}
	// Each shell that loads the file checks it.
	var shells []string
	if !strings.HasSuffix(name, ".zsh") {
		shells = append(shells, "bash")
	}
	if !strings.HasSuffix(name, ".bash") && HasCmd("zsh") {
		shells = append(shells, "zsh")
	}
	if len(shells) == 0 {
		s.Color(3, "zsh is not installed, so envsetup cannot check "+name+".")
	}
	for _, sh := range shells {
		if !s.checkConfig(add, "The text has an error in "+sh+", so envsetup saved nothing:", sh) {
			return ErrFailed
		}
		// The check below runs the text, so a dry run skips it.
		if s.DryRun {
			continue
		}
		// A file that runs exit would close every new shell.
		// zsh -f skips the user's own zsh startup files.
		// bash -f means something else (no globs), so bash gets only -c.
		opt := "-c"
		if sh == "zsh" {
			opt = "-fc"
		}
		c := s.Cmd(sh, opt, `. "$1" >/dev/null 2>&1; echo envsetup-ok`, "sh", add)
		c.Stdin, c.Stdout, c.Stderr = nil, nil, nil
		if out, _ := c.Output(); strings.TrimRight(string(out), "\n") != "envsetup-ok" {
			s.Color(1, "The text stops before its end in "+sh+", for example at an exit.",
				"Every new shell would then close. So envsetup saved nothing.")
			return ErrFailed
		}
	}
	if s.DryRun {
		s.Color(3, "A dry run does not run the text. It checks only the syntax.",
			"A real run also checks that the text runs to its end.")
	}
	file := s.ShellD + "/" + name
	if exists(file) {
		if s.DryRun {
			s.Would("ask to replace " + file)
			return nil
		}
		if yes, _ := s.UI.Confirm("Replace "+name+"?", true); !yes {
			s.Say("envsetup kept the old " + name + " and saved nothing.")
			return nil
		}
	}
	if s.DryRun {
		s.Would("save the text as " + file)
		return nil
	}
	if err := os.MkdirAll(s.ShellD, 0o777); err != nil {
		return err
	}
	// Replace a link itself, not the file that it points to.
	if err := os.Remove(file); err != nil && !errors.Is(err, fs.ErrNotExist) {
		return err
	}
	if err := os.WriteFile(file, []byte(text+"\n"), 0o666); err != nil {
		return err
	}
	s.Color(2, "Saved "+file+". New interactive shells load it.")
	return nil
}

// AddConfig adds the file's text to the end of config.sh (envsetup::add_config).
// Paste config and setup.sh --config use it.
func (s *Setup) AddConfig(file string) error {
	data, err := os.ReadFile(file)
	if err != nil {
		return err
	}
	return s.addConfig(string(data))
}

// addConfig adds the text to the end of config.sh.
// It saves nothing if the text is empty, or if bash -n finds an error in the text or in config.sh.
// It also saves nothing if config.sh would stop before its end, for example at an exit.
// A dry run checks only the syntax and adds nothing, because the other checks run the text.
func (s *Setup) addConfig(text string) error {
	text = cleanText(text)
	if blank(text) {
		s.Color(3, "The text is empty, so envsetup saved nothing.")
		return nil
	}
	add, newFile := s.Tmp+"/add.sh", s.Tmp+"/config.new"
	if err := os.WriteFile(add, []byte(text+"\n"), 0o666); err != nil {
		return err
	}
	if !s.checkConfig(add, "The text has an error, so envsetup saved nothing:", "bash") {
		return ErrFailed
	}
	var old []byte
	if isFile(s.UserConfig) {
		if !s.checkConfig(s.UserConfig, "config.sh already has an error, so envsetup saved nothing. Run envsetup config, or select Edit config, to fix it:", "bash") {
			return ErrFailed
		}
		var err error
		if old, err = os.ReadFile(s.UserConfig); err != nil {
			return err
		}
	}
	content := string(old)
	// A last line without a newline would join the first new line.
	if content != "" && !strings.HasSuffix(content, "\n") {
		content += "\n"
	}
	content += text + "\n"
	if err := os.WriteFile(newFile, []byte(content), 0o666); err != nil {
		return err
	}
	if !s.checkConfig(newFile, "config.sh with the text at its end has an error, so envsetup saved nothing:", "bash") {
		return ErrFailed
	}
	// settings_of runs config.sh and the text, so a dry run stops here.
	if s.DryRun {
		s.Would("add the text to the end of config.sh")
		s.Color(3, "A dry run does not run the text. It checks only the syntax.",
			"A real run also checks that config.sh runs to its end.", "Then it shows the changed settings.")
		return nil
	}
	before := s.SettingsOf(s.UserConfig)
	after := s.SettingsOf(newFile)
	if after == "" {
		s.Color(1, "config.sh with the text would stop before its end, for example at an exit.",
			"A new shell would then close. So envsetup saved nothing.")
		return ErrFailed
	}
	if err := os.MkdirAll(filepath.Dir(s.UserConfig), 0o777); err != nil {
		return err
	}
	// Like `cat new >file`: keep the mode and write through a link.
	if err := writeThrough(s.UserConfig, content); err != nil {
		return err
	}
	s.Color(2, "Added the text to the end of "+s.UserConfig)
	s.showChanges(before, after)
	s.warnConfigRepo()
	return nil
}

// checkConfig checks the file with `<shell> -n` (envsetup::check_config).
// On a syntax error, it shows the message and the error with its line number, and returns false.
func (s *Setup) checkConfig(file, msg, shell string) bool {
	c := s.Cmd(shell, "-n", file)
	c.Stdout, c.Stderr = nil, nil
	out, err := c.CombinedOutput()
	if err == nil {
		return true
	}
	s.Color(1, msg, syntaxError(strings.TrimRight(string(out), "\n"), file))
	return false
}

// syntaxError rewrites the error of `<shell> -n <file>` to name only the line.
// bash writes "<file>: line 2: …", and zsh writes "<file>:2: …".
func syntaxError(err, file string) string {
	err = strings.ReplaceAll(err, file+": ", "")
	return strings.ReplaceAll(err, file+":", "line ")
}

// settingLabels are the labels of settings_of, in the order that show_changes reports them.
var settingLabels = []string{"Packages", "Extras", "Skip", "Shell", "XDG ninja", "Git config", "Installer dirs"}

// showChanges compares two outputs of SettingsOf (envsetup::show_changes).
// It shows each setting that changed, for example "Packages: +neovim +zoxide".
func (s *Setup) showChanges(before, after string) {
	if after == "" {
		s.Color(3, "config.sh stops before its end, for example at an exit. So envsetup cannot show the changed settings.")
		return
	}
	lines := changes(before, after)
	if len(lines) == 0 {
		s.Say("No ENVSETUP_* setting changed.")
	}
	for _, line := range lines {
		s.Say(line)
	}
}

// changes returns one "<label>: +added -removed" line for each setting that changed.
func changes(before, after string) []string {
	set := func(text string) map[string]bool {
		m := map[string]bool{}
		for _, line := range strings.Split(text, "\n") {
			if line != "" {
				m[line] = true
			}
		}
		return m
	}
	old, new := set(before), set(after)
	var out []string
	for _, label := range settingLabels {
		diff := ""
		for _, line := range strings.Split(after, "\n") {
			if v, ok := strings.CutPrefix(line, label+"|"); ok && !old[line] {
				diff += " +" + v
			}
		}
		for _, line := range strings.Split(before, "\n") {
			if v, ok := strings.CutPrefix(line, label+"|"); ok && !new[line] {
				diff += " -" + v
			}
		}
		if diff != "" {
			out = append(out, label+":"+diff)
		}
	}
	return out
}
