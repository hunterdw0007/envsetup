// Package setup holds envsetup's menu, its actions and its options.
//
// Each action matches a function of the last bash release.
// The same machine and the same config.sh give the same result.
// tests/smoke.sh runs both versions and compares them (see "parity" there).
package setup

import (
	"errors"
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"syscall"

	"github.com/hunterdw0007/envsetup/internal/ui"
)

// The markers of the block that envsetup adds to ~/.bashrc and ~/.zshrc.
const (
	RCBegin = "# >>> envsetup >>>"
	RCEnd   = "# <<< envsetup <<<"
)

// Setup holds the state of one run.
// The bash version kept the same values in global variables.
type Setup struct {
	UI ui.UI
	// Root holds shell/, lib/, installers/, packages/, git/ and config.example.sh.
	// It is a clone when setup.sh runs the binary, and a temporary folder otherwise.
	Root string
	// Tmp is this run's temporary folder (ENVSETUP_TMP).
	// Installers run in their own processes and share it.
	Tmp string
	// Version is the release, as envsetup::version printed it.
	Version string
	DryRun  bool

	Home       string
	State      string // ENVSETUP_STATE: the user's files
	StateDir   string // STATE_DIR: where the menu saves its choices; a copy in a dry run
	Data       string // ENVSETUP_DATA: the copy of shell/ that new shells load
	Installed  string // ENVSETUP_INSTALLED: the record of installed tools
	ShellD     string // ENVSETUP_SHELL_D
	ChshMarker string // ENVSETUP_CHSH_MARKER
	SSHMarker  string // ENVSETUP_SSH_KEY_MARKER
	GitFile    string // ENVSETUP_GIT_GENERATED
	UserConfig string // ENVSETUP_USER_CONFIG; the copy in a dry run
	Clone      string // ENVSETUP_CONFIG_CLONE

	// Cfg is the config that the last Load read.
	Cfg *Config
	// warned is the last config warning shown (ENVSETUP_CONFIG_WARNED).
	warned string
	// asked is the checkout that drop_checkout asked about (ENVSETUP_ASKED).
	asked string
	// startEnv is the environment that envsetup started with.
	// Each load of config.sh starts from it, so a variable that config.sh no longer sets is gone.
	// It is nil in tests, which then keep the current environment.
	startEnv []string
}

// ErrFailed ends a step that already showed its error.
// run_step then shows only its own message, as the bash version did after `return 1`.
var ErrFailed = errors.New("step failed")

// ErrCancelled means that the user said no, and nothing changed.
// Uninstall returned 2 for it in the bash version.
var ErrCancelled = errors.New("cancelled")

// paths sets the paths from the environment, like shell/state.sh and lib/common.sh.
func (s *Setup) paths() {
	s.Home = os.Getenv("HOME")
	state := os.Getenv("ENVSETUP_STATE")
	if state == "" || os.Getenv("ENVSETUP_STATE_HOME") != s.Home {
		if x := os.Getenv("XDG_CONFIG_HOME"); strings.HasPrefix(x, "/") {
			state = x + "/envsetup"
		} else {
			state = s.Home + "/.config/envsetup"
		}
		if !isDir(state) && isDir(s.Home+"/.config/envsetup") {
			state = s.Home + "/.config/envsetup"
		}
	}
	s.State, s.StateDir = state, state
	s.ChshMarker = state + "/chsh"
	s.SSHMarker = state + "/ssh-key"
	s.ShellD = state + "/shell.d"
	s.GitFile = state + "/gitconfig"
	s.UserConfig = state + "/config.sh"
	s.Clone = state + "/repo"
	s.Data = xdg("XDG_DATA_HOME", s.Home+"/.local/share") + "/envsetup"
	s.Installed = xdg("XDG_STATE_HOME", s.Home+"/.local/state") + "/envsetup/installed"
}

// xdg returns an absolute XDG variable, or def.
// The XDG specification tells programs to ignore a relative value.
func xdg(name, def string) string {
	if v := os.Getenv(name); strings.HasPrefix(v, "/") {
		return v
	}
	return def
}

// CacheDir returns ${XDG_CACHE_HOME:-$HOME/.cache}/envsetup.
// Unlike the other XDG paths, the bash version used a relative XDG_CACHE_HOME too.
func (s *Setup) CacheDir() string {
	if v := os.Getenv("XDG_CACHE_HOME"); v != "" {
		return v + "/envsetup"
	}
	return s.Home + "/.cache/envsetup"
}

// Would describes a change that a dry run does not make (envsetup::would).
func (s *Setup) Would(text string) { s.UI.Print(ui.Note, "  would "+text) }

// Say shows a plain message.
func (s *Setup) Say(lines ...string) { s.UI.Print(ui.Plain, lines...) }

// Success shows a change that worked.
func (s *Setup) Success(lines ...string) { s.UI.Print(ui.Success, lines...) }

// Warn shows something the user should know, such as a skipped part.
func (s *Setup) Warn(lines ...string) { s.UI.Print(ui.Warn, lines...) }

// Fail shows an error.
func (s *Setup) Fail(lines ...string) { s.UI.Print(ui.Fail, lines...) }

// Note shows a note, such as what a dry run does.
func (s *Setup) Note(lines ...string) { s.UI.Print(ui.Note, lines...) }

// HasCmd reports whether the command is on PATH (envsetup::has_cmd).
func HasCmd(name string) bool {
	_, err := exec.LookPath(name)
	return err == nil
}

// Cmd prepares a command that uses the terminal, like a plain command in the bash version.
func (s *Setup) Cmd(name string, args ...string) *exec.Cmd {
	c := exec.Command(name, args...)
	c.Stdin, c.Stdout, c.Stderr = os.Stdin, os.Stdout, os.Stderr
	c.Env = s.Environ()
	return c
}

// Run runs a command on the terminal and returns its error.
func (s *Setup) Run(name string, args ...string) error { return s.Cmd(name, args...).Run() }

// Output runs a command and returns its stdout without the trailing newlines, like $(cmd).
// Its stderr goes to the terminal.
func (s *Setup) Output(name string, args ...string) (string, error) {
	return output(s.Cmd(name, args...), false)
}

// output runs c and returns its stdout without the trailing newlines, like $(cmd).
// quiet drops its stderr, like 2>/dev/null; otherwise stderr goes to the terminal.
func output(c *exec.Cmd, quiet bool) (string, error) {
	c.Stdout = nil
	if quiet {
		c.Stderr = nil
	}
	out, err := c.Output()
	return strings.TrimRight(string(out), "\n"), err
}

// Quiet runs a command with no output at all, like `cmd &>/dev/null`.
func (s *Setup) Quiet(name string, args ...string) error {
	c := s.Cmd(name, args...)
	c.Stdin, c.Stdout, c.Stderr = nil, nil, nil
	return c.Run()
}

// Environ is the environment for every command.
// The bash version exported ENVSETUP_ROOT and ENVSETUP_TMP.
// Installers source "$ENVSETUP_ROOT/lib/common.sh".
func (s *Setup) Environ() []string { return s.environ(os.Environ()) }

func (s *Setup) environ(base []string) []string {
	return append(slices.Clip(base), "ENVSETUP_ROOT="+s.Root, "ENVSETUP_TMP="+s.Tmp)
}

// AsRoot runs a command as root (envsetup::as_root).
// A user who is already root runs it directly (containers, WSL).
// Otherwise it uses sudo, or doas (Alpine).
func (s *Setup) AsRoot(args ...string) error {
	switch {
	case os.Geteuid() == 0:
		return s.Run(args[0], args[1:]...)
	case HasCmd("sudo"):
		return s.Run("sudo", args...)
	case HasCmd("doas"):
		return s.Run("doas", args...)
	}
	fmt.Fprintf(os.Stderr, "This command needs root, but this machine has no sudo or doas: %s\n", strings.Join(args, " "))
	return ErrFailed
}

// Lib runs a function of lib/common.sh, such as envsetup::pkg_install.
// Installers use those functions too, so they stay in bash and both share one copy.
func (s *Setup) Lib(fn string, args ...string) *exec.Cmd {
	return s.Cmd("bash", append([]string{"-c", `source "$ENVSETUP_ROOT/lib/common.sh" && "$@"`, "envsetup", fn}, args...)...)
}

// Quote quotes a value for bash and zsh, like printf %q.
func Quote(v string) string {
	out, err := exec.Command("bash", "-c", `printf %q "$1"`, "bash", v).Output()
	if err != nil {
		panic(err) // bash always runs here, because envsetup needs it for config.sh
	}
	return string(out)
}

// ReadState prints a saved choice, or def (envsetup::read_state).
// It returns the file's text without its trailing newlines, like $(<file).
func (s *Setup) ReadState(name, def string) string {
	b, err := os.ReadFile(filepath.Join(s.StateDir, name))
	if err != nil {
		return def
	}
	return strings.TrimRight(string(b), "\n")
}

// SaveState saves a choice (envsetup::save_state).
// An empty value deletes the choice.
func (s *Setup) SaveState(name, value string) error {
	if err := os.MkdirAll(s.StateDir, 0o777); err != nil {
		return err
	}
	if value == "" {
		err := os.Remove(filepath.Join(s.StateDir, name))
		if errors.Is(err, fs.ErrNotExist) {
			return nil
		}
		return err
	}
	return os.WriteFile(filepath.Join(s.StateDir, name), []byte(value+"\n"), 0o666)
}

// Lite reports whether this is work in lite mode (envsetup::lite).
// Lite mode does not assume sudo, so it runs no packages and no installers.
func (s *Setup) Lite() bool { return s.Cfg.Profile == "work" && s.Cfg.Mode == "lite" }

func isDir(p string) bool {
	fi, err := os.Stat(p)
	return err == nil && fi.IsDir()
}

// exists is true for any file, also for a link to a file that is gone, like [[ -e f || -L f ]].
func exists(p string) bool {
	_, err := os.Lstat(p)
	return err == nil
}

// isFile is like [[ -f f ]]: it follows links.
func isFile(p string) bool {
	fi, err := os.Stat(p)
	return err == nil && fi.Mode().IsRegular()
}

// exitCode returns the exit code of a command's error, like $?.
func exitCode(err error) int {
	var ee *exec.ExitError
	if errors.As(err, &ee) {
		if ws, ok := ee.Sys().(syscall.WaitStatus); ok && ws.Signaled() {
			return 128 + int(ws.Signal())
		}
		return ee.ExitCode()
	}
	if err != nil {
		return 1
	}
	return 0
}
