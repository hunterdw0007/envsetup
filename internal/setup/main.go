package setup

import (
	_ "embed"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strings"
	"sync"
	"syscall"

	"github.com/hunterdw0007/envsetup/internal/ui"
)

//go:embed usage.txt
var usage string

// cleanup holds the folders that every exit deletes, like setup.sh's EXIT trap.
// The signal handler reads it from another goroutine, so cleanupMu guards it.
var (
	cleanup   []string
	cleanupMu sync.Mutex
)

func addCleanup(dir string) {
	cleanupMu.Lock()
	defer cleanupMu.Unlock()
	cleanup = append(cleanup, dir)
}

// osExit and executable are os.Exit and os.Executable, so a test can replace them.
var (
	osExit     = os.Exit
	executable = os.Executable
)

// Exit deletes the temporary folders and ends envsetup with the code.
func (s *Setup) Exit(code int) {
	removeTemp()
	osExit(code)
}

func removeTemp() {
	cleanupMu.Lock()
	defer cleanupMu.Unlock()
	for _, d := range cleanup {
		os.RemoveAll(d)
	}
}

// Main runs envsetup with its options and returns the exit code (setup.sh).
func Main(args []string, version string) int {
	// A signal (Ctrl-C, a closed terminal, kill) deletes the temporary folders too.
	// Then envsetup ends by the same signal, so its parent sees 128+n, as with setup.sh.
	sigs := make(chan os.Signal, 1)
	done := make(chan struct{})
	signal.Notify(sigs, syscall.SIGINT, syscall.SIGTERM, syscall.SIGHUP)
	go func() {
		select {
		case sig := <-sigs:
			removeTemp()
			signal.Reset()
			_ = syscall.Kill(os.Getpid(), sig.(syscall.Signal))
		case <-done:
		}
	}()
	// The handler stops when Main returns, so each call in a test leaks nothing.
	defer func() {
		signal.Stop(sigs)
		close(done)
	}()
	defer removeTemp()

	s := &Setup{UI: ui.New(), startEnv: os.Environ()}
	s.paths()
	root, err := s.root()
	if err != nil {
		fmt.Fprintln(os.Stderr, "envsetup:", err)
		return 1
	}
	s.Root = root
	s.Version = s.version(version)

	var uninstall, editConfig bool
	var configFile string
	for i := 0; i < len(args); i++ {
		switch a := args[i]; a {
		case "-h", "--help":
			fmt.Print(usage)
			return 0
		case "--version":
			fmt.Println(s.Version)
			return 0
		case "--status":
			missing, err := s.Status()
			if err != nil {
				return exitOf(err)
			}
			if missing > 0 {
				return 1
			}
			return 0
		case "-n", "--dry-run":
			s.DryRun = true
		case "--uninstall":
			uninstall = true
		case "--edit-config":
			editConfig = true
		case "--config":
			next := ""
			if i+1 < len(args) {
				next = args[i+1]
			}
			if configFile != "" {
				fmt.Fprintln(os.Stderr, "setup.sh: use --config only once")
				return 2
			}
			if !readable(next) {
				fmt.Fprintf(os.Stderr, "setup.sh: --config needs a file that you can read: %s\n", next)
				return 2
			}
			configFile = next
			i++
		default:
			fmt.Fprintf(os.Stderr, "setup.sh: unknown option: %s\n\n", a)
			fmt.Fprint(os.Stderr, usage)
			return 2
		}
	}
	if uninstall && configFile != "" {
		fmt.Fprintln(os.Stderr, "setup.sh: --config and --uninstall do not work together")
		return 2
	}
	if editConfig && (uninstall || configFile != "") {
		fmt.Fprintln(os.Stderr, "setup.sh: --edit-config does not work with --config or --uninstall")
		return 2
	}

	// This run's temporary folder.
	// Installers run in their own processes and share it.
	if s.Tmp, err = os.MkdirTemp("", "tmp."); err != nil {
		fmt.Fprintln(os.Stderr, "envsetup:", err)
		return 1
	}
	addCleanup(s.Tmp)

	if s.DryRun {
		// Profile choices and config edits go to a temporary copy.
		// So the menu works as usual, and ~/.config/envsetup does not change.
		// The copy follows links, so a dry-run edit never reaches the config repo.
		s.StateDir = s.Tmp + "/state"
		if err := os.Mkdir(s.StateDir, 0o777); err != nil {
			fmt.Fprintln(os.Stderr, "envsetup:", err)
			return 1
		}
		copyTree(s.State, s.StateDir)
		s.UserConfig = s.StateDir + "/config.sh"
	}

	s.UI.Print(ui.Title, "envsetup "+s.Version)
	if s.DryRun {
		s.Note("Dry run: envsetup saves, installs and links nothing. Your choices and config edits last until you quit.")
	}
	if uninstall {
		// Uninstall needs the config to know which shell envsetup set up for your profile.
		s.LoadConfig(s.ReadState("profile", ""), s.ReadState("mode", "full"))
		// A cancelled uninstall is not an error.
		if err := s.Uninstall(); err != nil && !errors.Is(err, ErrCancelled) {
			return 1
		}
		return 0
	}
	if editConfig {
		s.Cfg = &Config{Profile: s.ReadState("profile", ""), Mode: s.ReadState("mode", "full")}
		// Under set -e, a failed editor ended setup.sh with the editor's own code.
		if err := s.EditConfig(); err != nil {
			return stepCode(err)
		}
		return 0
	}
	// run_step keeps a failure here from stopping setup before the menu.
	s.RunStep(s.SyncConfigRepo)
	s.RunStep(s.MigrateConfig)
	// --config runs after the sync, so the text goes to the end of the repo's config.sh.
	if configFile != "" {
		s.LoadConfig(s.ReadState("profile", ""), s.ReadState("mode", "full"))
		if err := s.AddConfig(configFile); err != nil {
			return stepCode(err)
		}
	}
	s.MainMenu()
	return 0
}

// root returns the folder with the files of this release: shell/, lib/, installers/ and so on.
// setup.sh sets ENVSETUP_FILES to its clone.
// Without it, the folder is the parent of the binary's folder, as in <clone>/bin/envsetup.
// It never reads ENVSETUP_ROOT, because each shell exports that variable as the copy of shell/.
func (s *Setup) root() (string, error) {
	if dir := os.Getenv("ENVSETUP_FILES"); dir != "" {
		return filepath.Abs(dir)
	}
	if exe, err := executable(); err == nil {
		if dir := filepath.Dir(filepath.Dir(exe)); isFile(dir + "/lib/common.sh") {
			return dir, nil
		}
	}
	return "", errors.New("run envsetup with setup.sh in its clone, or with install.sh")
}

// version prints the release, like envsetup::version.
// A clone prints `git describe`, such as v1.2.0-3-gabc1234.
// A built binary prints the release that it was built from.
// Otherwise it prints the release that copy_shell recorded.
func (s *Setup) version(built string) string {
	if out, err := exec.Command("git", "-C", s.Root, "describe", "--tags", "--match", "v[0-9]*", "--always", "--dirty").Output(); err == nil {
		return strings.TrimRight(string(out), "\n")
	}
	if built != "" {
		return built
	}
	if b, err := os.ReadFile(s.Data + "/version"); err == nil {
		return strings.TrimRight(string(b), "\n")
	}
	return "unknown"
}

func readable(p string) bool {
	if !isFile(p) {
		return false
	}
	f, err := os.Open(p)
	if err != nil {
		return false
	}
	f.Close()
	return true
}

// copyTree copies a folder like `cp -rL src/. dst/`, and ignores errors like `2>/dev/null || true`.
func copyTree(src, dst string) {
	entries, err := os.ReadDir(src)
	if err != nil {
		return
	}
	for _, e := range entries {
		from, to := filepath.Join(src, e.Name()), filepath.Join(dst, e.Name())
		fi, err := os.Stat(from) // follows links
		if err != nil {
			continue
		}
		if fi.IsDir() {
			if os.MkdirAll(to, fi.Mode().Perm()) == nil {
				copyTree(from, to)
			}
			continue
		}
		if data, err := os.ReadFile(from); err == nil {
			_ = os.WriteFile(to, data, fi.Mode().Perm())
		}
	}
}

// RunStep runs a menu action (envsetup::run_step).
// A failure returns to the menu and does not end envsetup.
func (s *Setup) RunStep(step func() error) {
	// bash ran each step in a subshell, so each step started without the state of the last one.
	s.asked = ""
	err := step()
	if err == nil {
		return
	}
	var ee *exec.ExitError
	var ce *ExitError
	if !errors.Is(err, ErrFailed) && !errors.As(err, &ee) && !errors.As(err, &ce) {
		// bash showed the error of a failed command itself, such as mkdir's.
		fmt.Fprintln(os.Stderr, err)
	}
	s.Fail("That step didn't finish. The error is above. Fix it and run the step again.")
}

// stepCode is the exit code that a failed top-level step gave setup.sh under set -e.
// A failed command gave its own code, and every other failure gave 1.
func stepCode(err error) int {
	var ee *exec.ExitError
	if errors.As(err, &ee) {
		return exitCode(err)
	}
	return exitOf(err)
}
