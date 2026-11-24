package setup

import (
	"bytes"
	"os"
	"strconv"
	"strings"

	"github.com/hunterdw0007/envsetup/internal/ui"
)

// Config holds the settings after config.sh ran.
// config.sh is bash and can run any bash code.
// So bash loads it with envsetup::load_config from lib/config.sh, and Go reads the result.
type Config struct {
	Profile, Mode string

	Packages      []string // ENVSETUP_PACKAGES
	GitConfig     []string // ENVSETUP_GIT_CONFIG, as key=value
	InstallerDirs []string // ENVSETUP_INSTALLER_DIRS
	Extras        []string // ENVSETUP_EXTRAS
	Skip          []string // ENVSETUP_SKIP
	Shell         string   // ENVSETUP_SHELL
	XDGNinja      string   // ENVSETUP_XDG_NINJA
	Renamed       []string // ENVSETUP_RENAMED, as old=new
	// RepoURL is ENVSETUP_REPO_URL, also when config.sh sets it without export.
	RepoURL string

	// Packages is what envsetup::resolved_packages prints.
	ResolvedPackages []string
	// ResolvedInstallers is what envsetup::resolved_installers prints: script paths.
	ResolvedInstallers []string
	// InstallersErr is what envsetup::resolved_installers wrote to stderr.
	// The bash version showed it each time an action listed the installers.
	InstallersErr string
	// Warning is the warning of load_config, such as a syntax error in config.sh.
	Warning string

	// env lists the environment variables that config.sh changed: "NAME=value", or "NAME" when unset.
	env []string
}

// loadScript loads the config and writes each value to the file in $4.
// A file, not a pipe: a background job of config.sh would hold a pipe open, and Go would wait for that job.
// config.sh's own output still goes to stdout and stderr.
// Each value is "<name>\0<count>\0<item>\0...".
const loadScript = `
source "$ENVSETUP_ROOT/lib/common.sh" || exit 1
source "$ENVSETUP_ROOT/lib/config.sh" || exit 1
envsetup::config_warning() { ENVSETUP_CONFIG_WARNED=$1; }
ENVSETUP_CONFIG_WARNED=
ENVSETUP_USER_CONFIG=$3
_ENVSETUP_DUMP=$4
_envsetup_dump() { local -n _envsetup_v=$1; printf '%s\0' "$1" "${#_envsetup_v[@]}" "${_envsetup_v[@]}" >>"$_ENVSETUP_DUMP"; }
readarray -d '' _ENV_BEFORE < <(env -0)
envsetup::load_config "$1" "$2"
readarray -d '' _ENV_AFTER < <(env -0)
readarray -t RESOLVED_PACKAGES < <(envsetup::resolved_packages)
readarray -t RESOLVED_INSTALLERS < <(envsetup::resolved_installers 2>/dev/null)
INSTALLERS_ERR=$(envsetup::resolved_installers 2>&1 >/dev/null)
for _envsetup_name in ENVSETUP_PACKAGES ENVSETUP_GIT_CONFIG ENVSETUP_INSTALLER_DIRS ENVSETUP_EXTRAS ENVSETUP_SKIP \
	ENVSETUP_SHELL ENVSETUP_XDG_NINJA ENVSETUP_RENAMED ENVSETUP_CONFIG_WARNED RESOLVED_PACKAGES RESOLVED_INSTALLERS \
	INSTALLERS_ERR ENVSETUP_REPO_URL _ENV_BEFORE _ENV_AFTER; do
	_envsetup_dump "$_envsetup_name"
done
`

// ExitError means that config.sh ran exit.
// The bash version sourced config.sh, so that exit ended setup.sh with the same code.
type ExitError struct{ Code int }

func (e *ExitError) Error() string { return "config.sh exited with " + strconv.Itoa(e.Code) }

// Load runs envsetup::load_config with that file as config.sh.
// quiet drops config.sh's own output, like `load_config >/dev/null 2>&1`.
func (s *Setup) Load(profile, mode, file string, quiet bool) (*Config, error) {
	dump, err := os.CreateTemp("", "envsetup-config.")
	if err != nil {
		return nil, err
	}
	dump.Close()
	defer os.Remove(dump.Name())
	c := s.Cmd("bash", "-c", loadScript, "envsetup", profile, mode, file, dump.Name())
	if s.startEnv != nil {
		c.Env = s.environ(s.startEnv)
	}
	if quiet {
		c.Stdin, c.Stdout, c.Stderr = nil, nil, nil
	}
	err = c.Run()
	data, _ := os.ReadFile(dump.Name())
	vals := parseDump(data)
	if _, done := vals["_ENV_AFTER"]; !done {
		// config.sh ran exit, also `exit 0`, which ended setup.sh with that code.
		return nil, &ExitError{exitCode(err)}
	}
	first := func(name string) string {
		if v := vals[name]; len(v) > 0 {
			return v[0]
		}
		return ""
	}
	return &Config{
		Profile: profile, Mode: mode,
		Packages: vals["ENVSETUP_PACKAGES"], GitConfig: vals["ENVSETUP_GIT_CONFIG"],
		InstallerDirs: vals["ENVSETUP_INSTALLER_DIRS"], Extras: vals["ENVSETUP_EXTRAS"], Skip: vals["ENVSETUP_SKIP"],
		Shell: first("ENVSETUP_SHELL"), XDGNinja: first("ENVSETUP_XDG_NINJA"), Renamed: vals["ENVSETUP_RENAMED"],
		RepoURL:          first("ENVSETUP_REPO_URL"),
		ResolvedPackages: nonEmpty(vals["RESOLVED_PACKAGES"]), ResolvedInstallers: nonEmpty(vals["RESOLVED_INSTALLERS"]),
		InstallersErr: first("INSTALLERS_ERR"), Warning: first("ENVSETUP_CONFIG_WARNED"),
		env: envDiff(vals["_ENV_BEFORE"], vals["_ENV_AFTER"]),
	}, nil
}

// LoadConfig loads the config for the menu and the actions (envsetup::load_config).
// It shows a new warning once, and keeps the environment that config.sh exported, as sourcing it did.
// Unlike sourcing, a later load drops what an earlier load exported.
// A config.sh that runs exit ends envsetup with that code, as it ended setup.sh.
func (s *Setup) LoadConfig(profile, mode string) {
	cfg, err := s.Load(profile, mode, s.UserConfig, false)
	if err != nil {
		s.Exit(exitOf(err))
	}
	s.Cfg = cfg
	s.setenv(cfg)
	s.ShowWarning(cfg.Warning)
}

// ShowWarning shows a config warning only once, until the text changes (envsetup::config_warning).
func (s *Setup) ShowWarning(w string) {
	if w != "" && w != s.warned {
		s.warned = w
		s.UI.Eprint(ui.Warn, w)
	}
}

func exitOf(err error) int {
	if e, ok := err.(*ExitError); ok {
		return e.Code
	}
	return 1
}

// SettingsOf prints the settings with that file as config.sh (envsetup::settings_of).
// It prints one "<label>|<value>" line for each value, and nothing when config.sh runs exit.
func (s *Setup) SettingsOf(file string) string {
	c := s.Cmd("bash", "-c", `source "$ENVSETUP_ROOT/lib/common.sh" && source "$ENVSETUP_ROOT/lib/config.sh" &&
ENVSETUP_PROFILE=$1 ENVSETUP_MODE=$2 envsetup::settings_of "$3"`, "envsetup", s.cfgProfile(), s.cfgMode(), file)
	c.Stdin, c.Stdout, c.Stderr = nil, nil, nil
	out, _ := c.Output()
	return strings.TrimRight(string(out), "\n")
}

func (s *Setup) cfgProfile() string {
	if s.Cfg == nil {
		return ""
	}
	return s.Cfg.Profile
}

func (s *Setup) cfgMode() string {
	if s.Cfg == nil || s.Cfg.Mode == "" {
		return "full"
	}
	return s.Cfg.Mode
}

func parseDump(data []byte) map[string][]string {
	vals := map[string][]string{}
	f := bytes.Split(data, []byte{0})
	for i := 0; i+1 < len(f); {
		name := string(f[i])
		n, err := strconv.Atoi(string(f[i+1]))
		// A count below 0 would panic in make, and i+2+n can overflow.
		if err != nil || n < 0 || n > len(f)-i-2 {
			break
		}
		items := make([]string, n)
		for j := range n {
			items[j] = string(f[i+2+j])
		}
		vals[name] = items
		i += 2 + n
	}
	return vals
}

// nonEmpty drops the one empty item that readarray makes from empty output.
func nonEmpty(v []string) []string {
	if len(v) == 1 && v[0] == "" {
		return nil
	}
	return v
}

func envDiff(before, after []string) []string {
	old := map[string]string{}
	for _, kv := range before {
		name, value, _ := strings.Cut(kv, "=")
		old[name] = value
	}
	var diff []string
	for _, kv := range after {
		name, value, _ := strings.Cut(kv, "=")
		if v, ok := old[name]; !ok || v != value {
			diff = append(diff, kv)
		}
		delete(old, name)
	}
	for name := range old {
		if name != "_" {
			diff = append(diff, name)
		}
	}
	return diff
}
