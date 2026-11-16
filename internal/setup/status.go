package setup

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// This file holds "Check status" and setup.sh --status.
// The check reads the machine and changes nothing.
// So it needs no dry-run checks, and it works without gum.
// Each line starts with "ok" or "missing".

// statusLines counts the missing lines (envsetup::status_line).
type statusLines struct{ missing int }

// line prints one line and counts each missing line.
func (l *statusLines) line(kind, text string) {
	fmt.Printf("%-8s %s\n", kind, text)
	if kind == "missing" {
		l.missing++
	}
}

// Status prints one line for each part of the setup (envsetup::status).
// It returns the number of missing lines.
func (s *Setup) Status() int {
	var l statusLines

	newest := s.newestRelease()
	if newest == "" {
		newest = "unknown, GitHub is out of reach"
	}
	newest = "newest release: " + newest
	if b, err := os.ReadFile(s.Data + "/version"); isFile(s.Data+"/version") && err == nil {
		l.line("ok", "new shells use "+strings.TrimRight(string(b), "\n")+" ("+newest+")")
	} else {
		l.line("missing", "no copy of shell/ in "+s.Data+". Select Link shell config ("+newest+")")
	}

	profile, mode := s.ReadState("profile", ""), s.ReadState("mode", "full")
	cfg, err := s.Load(profile, mode, s.UserConfig, true)
	if err != nil {
		// config.sh ran exit, which ended setup.sh in the bash version.
		s.Exit(exitOf(err))
	}
	// The bash version loaded the config into its own shell, like LoadConfig.
	s.Cfg = cfg
	cfg.setenv()
	s.warned = cfg.Warning
	switch profile {
	case "":
		l.line("missing", "no saved profile. Select a profile in the menu")
	case "work":
		l.line("ok", "profile: work ("+mode+")")
	default:
		l.line("ok", "profile: "+profile)
	}

	for _, rc := range []string{s.Home + "/.bashrc", s.Home + "/.zshrc"} {
		if strings.HasSuffix(rc, "/.zshrc") && filepath.Base(os.Getenv("SHELL")) != "zsh" && cfg.Shell != "zsh" {
			continue
		}
		if b, err := os.ReadFile(rc); err == nil && strings.Contains(string(b), RCBegin) {
			l.line("ok", rc+" has the envsetup block")
		} else {
			l.line("missing", rc+" has no envsetup block. Select Link shell config")
		}
	}

	if s.GitIncluded() {
		l.line("ok", s.Home+"/.gitconfig includes "+s.GitFile)
	} else {
		l.line("missing", s.Home+"/.gitconfig does not include "+s.GitFile+". Select Configure git")
	}

	// Work lite installs nothing, and without a profile nothing is chosen yet.
	if profile != "" && !s.Lite() {
		s.statusPackages(&l)
		s.statusInstallers(&l)
	}

	switch {
	case cfg.Warning != "":
		l.line("missing", cfg.Warning)
	case isFile(s.UserConfig):
		l.line("ok", s.UserConfig+" loads without errors")
	default:
		l.line("ok", "no "+s.UserConfig+", so envsetup uses its defaults")
	}
	return l.missing
}

func (s *Setup) statusPackages(l *statusLines) {
	c := s.Lib("envsetup::pkg_manager")
	c.Stdout, c.Stderr = nil, nil
	out, _ := c.Output()
	manager := strings.TrimRight(string(out), "\n")
	pkgs := s.Cfg.ResolvedPackages
	before := l.missing
	if manager == "" {
		l.line("missing", fmt.Sprintf("no supported package manager, so envsetup cannot check %d packages", len(pkgs)))
	} else {
		for _, pkg := range pkgs {
			if name := s.PkgName(manager, pkg); name != "" && !s.pkgInstalled(manager, name) {
				l.line("missing", "package "+pkg+" is not installed. Select Install packages")
			}
		}
	}
	if before == l.missing {
		l.line("ok", fmt.Sprintf("all %d packages are installed", len(pkgs)))
	}
}

func (s *Setup) statusInstallers(l *statusLines) {
	scripts := s.Cfg.ResolvedInstallers
	before := l.missing
	for i, name := range installerNames(scripts) {
		data, _ := os.ReadFile(scripts[i])
		cmd := installerCmd(string(data))
		if cmd == "" {
			continue
		}
		record := s.InstalledVersion(name)
		pin, err := s.Pin(name)
		if err != nil {
			pin = ""
		}
		if !HasCmd(cmd) {
			l.line("missing", cmd+" is not on PATH. Select Run installers")
		} else if record != "" && pin != "" && record != pin {
			l.line("missing", name+" "+record+" differs from the pin "+pin+". Select Run installers")
		}
	}
	if before == l.missing {
		l.line("ok", fmt.Sprintf("no tool from %d installers is missing", len(scripts)))
	}
}

// A tool installer exits early with "envsetup::has_cmd <command> && exit 0".
// A pinned one uses "envsetup::up_to_date <name> <command> && exit 0" instead.
// Other installers are setup steps without a tool, so the check skips them.
var installerCheck = regexp.MustCompilePOSIX(`^envsetup::(has_cmd|up_to_date [^ ]+) ([^ ]+) && exit 0`)

// installerCmd returns the command of the last early-exit check in a script, or "".
// Like `while read -r line`, it trims spaces and tabs, and skips a last line without a newline.
func installerCmd(script string) string {
	lines := strings.Split(script, "\n")
	cmd := ""
	for _, line := range lines[:len(lines)-1] {
		if m := installerCheck.FindStringSubmatch(strings.Trim(line, " \t")); m != nil {
			cmd = m[2]
		}
	}
	return cmd
}

var releaseTag = regexp.MustCompile(`refs/tags/(v[0-9]*\.[0-9]*\.[0-9]*)$`)

// newestRelease prints the newest release tag in the envsetup repo (envsetup::newest_release).
// It prints nothing when the repo is out of reach, for example offline.
func (s *Setup) newestRelease() string {
	url := os.Getenv("ENVSETUP_REPO_URL")
	// The menu loaded config.sh before, and the bash version kept its variables, also those without export.
	if s.Cfg != nil {
		url = s.Cfg.RepoURL
	}
	if url == "" {
		url = "https://github.com/hunterdw0007/envsetup.git"
	}
	c := s.Cmd("timeout", "10", "git", "ls-remote", "--tags", "--refs", url, "v*")
	c.Env = append(c.Env, "GIT_TERMINAL_PROMPT=0")
	c.Stdin, c.Stdout, c.Stderr = nil, nil, nil
	out, _ := c.Output()
	return newestTag(string(out))
}

// newestTag picks the highest vX.Y.Z tag from `git ls-remote` output, like `sed | sort -V | tail -n 1`.
func newestTag(lsRemote string) string {
	best := ""
	for _, line := range strings.Split(lsRemote, "\n") {
		if m := releaseTag.FindStringSubmatch(line); m != nil && (best == "" || versionCompare(m[1], best) >= 0) {
			best = m[1]
		}
	}
	return best
}

// versionCompare orders two strings like `sort -V` (GNU filevercmp without file suffixes).
// Runs of digits compare as numbers, and the other characters compare in Debian's version order.
// Equal versions fall back to plain string order, as sort does.
func versionCompare(a, b string) int {
	if r := verrevcmp(a, b); r != 0 {
		return r
	}
	return strings.Compare(a, b)
}

func isDigit(c byte) bool { return '0' <= c && c <= '9' }

// order ranks a character: digits and the end first, then letters, then everything else.
func order(s string, i int) int {
	switch {
	case i >= len(s):
		return 0
	case isDigit(s[i]):
		return 0
	case ('a' <= s[i] && s[i] <= 'z') || ('A' <= s[i] && s[i] <= 'Z'):
		return int(s[i])
	case s[i] == '~':
		return -1
	default:
		return int(s[i]) + 256
	}
}

func verrevcmp(a, b string) int {
	i, j := 0, 0
	for i < len(a) || j < len(b) {
		first := 0
		for (i < len(a) && !isDigit(a[i])) || (j < len(b) && !isDigit(b[j])) {
			if ac, bc := order(a, i), order(b, j); ac != bc {
				return ac - bc
			}
			i++
			j++
		}
		for i < len(a) && a[i] == '0' {
			i++
		}
		for j < len(b) && b[j] == '0' {
			j++
		}
		for i < len(a) && isDigit(a[i]) && j < len(b) && isDigit(b[j]) {
			if first == 0 {
				first = int(a[i]) - int(b[j])
			}
			i++
			j++
		}
		if i < len(a) && isDigit(a[i]) {
			return 1
		}
		if j < len(b) && isDigit(b[j]) {
			return -1
		}
		if first != 0 {
			return first
		}
	}
	return 0
}

// setenv keeps the environment that config.sh exported, as sourcing it did.
func (c *Config) setenv() {
	for _, kv := range c.env {
		if name, value, ok := strings.Cut(kv, "="); ok {
			os.Setenv(name, value)
		} else {
			os.Unsetenv(name)
		}
	}
}
