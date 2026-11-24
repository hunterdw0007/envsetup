package setup

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

// This file tests Install packages, Run installers and the package helpers around them.

// managerCmds maps each package manager to the command that PkgManager looks for.
var managerCmds = map[string]string{
	"apt": "apt-get", "dnf": "dnf", "zypper": "zypper", "pacman": "pacman", "apk": "apk", "brew": "brew", "nix": "nix-env",
}

// onlyManager leaves one package manager on PATH, as a fake that succeeds.
func onlyManager(f *fakes, manager string) {
	for m, c := range managerCmds {
		if m != manager {
			f.remove(c)
		}
	}
	f.set(managerCmds[manager], fakeCmd{})
}

// asUser makes AsRoot act as a normal user, or as root with uid 0.
func asUser(t *testing.T, uid int) {
	geteuid = func() int { return uid }
	t.Cleanup(func() { geteuid = os.Geteuid })
}

// fakeOSRelease gives s a root whose lib/common.sh reads these /etc/os-release fields.
// The rest of the root links to this repo.
func fakeOSRelease(t *testing.T, s *Setup, fields map[string]string) {
	t.Helper()
	dir := t.TempDir()
	for _, name := range []string{"packages", "installers", "shell", "git"} {
		if err := os.Symlink(filepath.Join(s.Root, name), filepath.Join(dir, name)); err != nil {
			t.Fatal(err)
		}
	}
	lib := fmt.Sprintf("source %q\nenvsetup::os_release() {\n\tcase $1 in\n", s.Root+"/lib/common.sh")
	for k, v := range fields {
		lib += fmt.Sprintf("\t%s) echo %q ;;\n", k, v)
	}
	lib += "\tesac\n}\n"
	if err := os.Mkdir(dir+"/lib", 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(dir+"/lib/common.sh", []byte(lib), 0o644); err != nil {
		t.Fatal(err)
	}
	s.Root = dir
}

// callsOf returns the calls to these commands only.
// The bash helpers call sudo only when the test runs as a normal user, so the tests leave sudo out.
func callsOf(f *fakes, names ...string) []string {
	var out []string
	for _, c := range f.rawCalls() {
		if slices.Contains(names, c[0]) {
			out = append(out, strings.Join(c, " "))
		}
	}
	return out
}

func logHas(u *fakeUI, line string) bool {
	return slices.ContainsFunc(u.log, func(l string) bool { return strings.Contains(l, line) })
}

func TestAsRoot(t *testing.T) {
	sandbox(t)
	f := fakeCommands(t)
	f.set("apt-get", fakeCmd{})
	f.set("sudo", fakeCmd{})
	f.set("doas", fakeCmd{})
	s := &Setup{}
	run := func(want ...string) {
		t.Helper()
		before := len(f.calls())
		if err := s.AsRoot("apt-get", "update"); err != nil {
			t.Fatal(err)
		}
		if got := f.calls()[before:]; !slices.Equal(got, want) {
			t.Errorf("calls = %q, want %q", got, want)
		}
	}
	asUser(t, 0)
	run("apt-get update")
	asUser(t, 1000)
	run("sudo apt-get update")
	f.remove("sudo")
	run("doas apt-get update")
	f.remove("doas")
	before := len(f.calls())
	if err := s.AsRoot("apt-get", "update"); !errors.Is(err, ErrFailed) {
		t.Errorf("AsRoot with neither sudo nor doas = %v, want ErrFailed", err)
	}
	if got := f.calls()[before:]; len(got) > 0 {
		t.Errorf("AsRoot with neither ran %q", got)
	}
	f.cmds["sudo"], f.cmds["doas"] = fakeCmd{}, fakeCmd{} // the calls above were on purpose
}

func TestPackageManagers(t *testing.T) {
	pkgs := []string{"vim", "dnsutils", "openssh-client", "npm"}
	tests := []struct {
		manager string
		names   []string // the names from packages/names.txt; "" means none
		install string   // the call of the manager
	}{
		{"apt", []string{"vim", "dnsutils", "openssh-client", "npm"}, "apt-get install -y vim dnsutils openssh-client npm"},
		{"dnf", []string{"vim-enhanced", "bind-utils", "openssh-clients", "npm"}, "dnf install -y vim-enhanced bind-utils openssh-clients npm"},
		{"zypper", []string{"vim", "bind-utils", "openssh-clients", "npm-default"}, "zypper --non-interactive install vim bind-utils openssh-clients npm-default"},
		{"pacman", []string{"vim", "bind", "openssh", "npm"}, "pacman -S --noconfirm --needed vim bind openssh npm"},
		{"apk", []string{"vim", "bind-tools", "openssh-client", "npm"}, "apk add vim bind-tools openssh-client npm"},
		{"brew", []string{"vim", "bind", "", ""}, "brew install vim bind"},
		{"nix", []string{"vim", "dnsutils", "openssh", ""}, "nix-env -f <nixpkgs> -iA vim dnsutils openssh"},
	}
	for _, tt := range tests {
		t.Run(tt.manager, func(t *testing.T) {
			sandbox(t)
			f := fakeCommands(t)
			onlyManager(f, tt.manager)
			f.set("sudo", fakeCmd{Real: "/usr/bin/env"})
			f.set("nix", fakeCmd{Code: 1}) // no new-style nix profile
			s := &Setup{Root: os.Getenv("ENVSETUP_FILES"), Tmp: t.TempDir()}
			if got := s.PkgManager(); got != tt.manager {
				t.Fatalf("PkgManager = %q, want %q", got, tt.manager)
			}
			for i, pkg := range pkgs {
				if got := s.PkgName(tt.manager, pkg); got != tt.names[i] {
					t.Errorf("PkgName(%s, %s) = %q, want %q", tt.manager, pkg, got, tt.names[i])
				}
			}
			if err := s.PkgInstall(tt.manager, pkgs...); err != nil {
				t.Fatal(err)
			}
			if got := callsOf(f, managerCmds[tt.manager]); !slices.Contains(got, tt.install) {
				t.Errorf("calls = %q, want %q", got, tt.install)
			}
		})
	}
	t.Run("nix profile", func(t *testing.T) {
		sandbox(t)
		f := fakeCommands(t)
		onlyManager(f, "nix")
		f.set("nix", fakeCmd{})
		s := &Setup{Root: os.Getenv("ENVSETUP_FILES"), Tmp: t.TempDir()}
		if err := s.PkgInstall("nix", "vim"); err != nil {
			t.Fatal(err)
		}
		if got := callsOf(f, "nix"); !slices.Contains(got, "nix profile install nixpkgs#vim") {
			t.Errorf("calls = %q, want nix profile install nixpkgs#vim", got)
		}
	})
}

func TestPkgInstalled(t *testing.T) {
	sandbox(t)
	f := fakeCommands(t)
	s := &Setup{}
	tests := []struct {
		manager, cmd, call string
		yes, no            fakeCmd
	}{
		{"apt", "dpkg-query", "dpkg-query -W -f=${Status} vim", fakeCmd{Out: "install ok installed"}, fakeCmd{Out: "unknown ok not-installed", Code: 1}},
		{"dnf", "rpm", "rpm -q --whatprovides vim", fakeCmd{}, fakeCmd{Code: 1}},
		{"zypper", "rpm", "rpm -q --whatprovides vim", fakeCmd{}, fakeCmd{Code: 1}},
		{"pacman", "pacman", "pacman -T vim", fakeCmd{}, fakeCmd{Code: 127}},
		{"apk", "apk", "apk info -e vim", fakeCmd{}, fakeCmd{Code: 1}},
		{"brew", "brew", "brew list vim", fakeCmd{}, fakeCmd{Code: 1}},
		{"nix", "nix-env", "nix-env -q vim", fakeCmd{}, fakeCmd{Code: 1}},
	}
	f.set("nix", fakeCmd{Out: "Index: 0\nFlake attribute: legacyPackages.x86_64-linux.git\n"})
	for _, tt := range tests {
		f.set(tt.cmd, tt.yes)
		if !s.pkgInstalled(tt.manager, "vim") {
			t.Errorf("%s: pkgInstalled = false, want true", tt.manager)
		}
		if c := f.calls(); c[len(c)-1] != tt.call {
			t.Errorf("%s: last call %q, want %q", tt.manager, c[len(c)-1], tt.call)
		}
		f.set(tt.cmd, tt.no)
		if s.pkgInstalled(tt.manager, "vim") {
			t.Errorf("%s: pkgInstalled = true, want false", tt.manager)
		}
	}
	// A new-style nix profile lists the package as <attribute path>.<name>.
	f.set("nix", fakeCmd{Out: "Flake attribute: legacyPackages.x86_64-linux.vim\n"})
	if !s.pkgInstalled("nix", "vim") {
		t.Error("nix profile: pkgInstalled = false, want true")
	}
	if s.pkgInstalled("unknown", "vim") {
		t.Error("an unknown manager has the package")
	}
}

func TestInstallPackages(t *testing.T) {
	s, u, f := newTestSetup(t, "home", "full")
	onlyManager(f, "apt")
	f.set("sudo", fakeCmd{Real: "/usr/bin/env"})
	var names []string
	for _, pkg := range s.Cfg.ResolvedPackages {
		names = append(names, s.PkgName("apt", pkg))
	}
	if len(names) < 5 {
		t.Fatalf("the home profile resolved only %q", names)
	}
	install := "apt-get install -y " + strings.Join(names, " ")

	// Dry run: nothing changes, and the action says what it would install.
	s.DryRun = true
	before := snapshotHome(t)
	if err := s.InstallPackages(); err != nil {
		t.Fatal(err)
	}
	want := fmt.Sprintf("note:   would install %d packages with apt (as root), and skip the ones already installed: %s", len(names), strings.Join(names, " "))
	if !slices.Equal(u.log, []string{want}) {
		t.Errorf("dry run log = %q, want %q", u.log, want)
	}
	if d := diffSnapshots(before, snapshotHome(t)); len(d) > 0 {
		t.Errorf("the dry run changed HOME: %q", d)
	}
	if c := callsOf(f, "apt-get"); len(c) > 0 {
		t.Errorf("the dry run ran %q", c)
	}

	// First run: apt-get updates once, then installs every package in one call.
	s.DryRun = false
	if err := s.InstallPackages(); err != nil {
		t.Fatal(err)
	}
	if got := callsOf(f, "apt-get"); !slices.Equal(got, []string{"apt-get update", install}) {
		t.Errorf("first run: calls = %q, want update, then %q", got, install)
	}
	// Second run: the same run does not update again, and apt-get skips what it has.
	if err := s.InstallPackages(); err != nil {
		t.Fatal(err)
	}
	if got := callsOf(f, "apt-get"); !slices.Equal(got, []string{"apt-get update", install, install}) {
		t.Errorf("second run: calls = %q, want no second update", got)
	}
}

func TestInstallPackagesSkip(t *testing.T) {
	s, _, f := newTestSetup(t, "home", "full")
	if err := os.MkdirAll(filepath.Dir(s.UserConfig), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(s.UserConfig, []byte("ENVSETUP_SKIP=(vim)\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	f.passThrough("git") // lib/config.sh reads git/gitconfig
	cfg, err := s.Load("home", "full", s.UserConfig, true)
	if err != nil {
		t.Fatal(err)
	}
	s.Cfg = cfg
	if slices.Contains(cfg.ResolvedPackages, "vim") || !slices.Contains(cfg.ResolvedPackages, "curl") {
		t.Fatalf("ResolvedPackages = %q, want curl and no vim", cfg.ResolvedPackages)
	}
	onlyManager(f, "brew")
	if err := s.InstallPackages(); err != nil {
		t.Fatal(err)
	}
	got := callsOf(f, "brew")
	if len(got) != 1 || !strings.HasPrefix(got[0], "brew install ") || slices.Contains(strings.Fields(got[0]), "vim") {
		t.Errorf("calls = %q, want one brew install without vim", got)
	}
}

// Lite mode installs nothing and runs no installers.
func TestInstallPackagesLite(t *testing.T) {
	s, u, f := newTestSetup(t, "work", "lite")
	if err := s.InstallPackages(); err != nil {
		t.Fatal(err)
	}
	if err := s.RunInstallers(); err != nil {
		t.Fatal(err)
	}
	if !logHas(u, "installs no packages") || !logHas(u, "runs no installers") {
		t.Errorf("lite log = %q", u.log)
	}
	if c := f.calls(); len(c) > 0 {
		t.Errorf("lite mode ran %q", c)
	}

}

func TestInstallPackagesNoManager(t *testing.T) {
	s, u, f := newTestSetup(t, "home", "full")
	for _, c := range managerCmds {
		f.remove(c)
	}
	if err := s.InstallPackages(); !errors.Is(err, ErrFailed) || !logHas(u, "No supported package manager found.") {
		t.Errorf("no manager: %v, log %q", err, u.log)
	}

	// brew needs none of these packages.
	onlyManager(f, "brew")
	s.Cfg.ResolvedPackages = []string{"openssh-client", "npm"}
	if err := s.InstallPackages(); err != nil || !logHas(u, "No packages listed for home.") {
		t.Errorf("no names: %v, log %q", err, u.log)
	}
	if c := callsOf(f, "brew"); len(c) > 0 {
		t.Errorf("brew ran %q", c)
	}
}

func TestInstallPackagesDNF(t *testing.T) {
	s, u, f := newTestSetup(t, "home", "full")
	fakeOSRelease(t, s, map[string]string{"ID": "fedora"})
	onlyManager(f, "dnf")
	f.set("sudo", fakeCmd{Real: "/usr/bin/env"})
	s.DryRun = true
	if err := s.InstallPackages(); err != nil {
		t.Fatal(err)
	}
	if !logHas(u, "with dnf (as root)") {
		t.Errorf("log = %q", u.log)
	}
	s.DryRun = false
	if err := s.InstallPackages(); err != nil {
		t.Fatal(err)
	}
	got := callsOf(f, "dnf", "rpm")
	if len(got) != 1 || !strings.HasPrefix(got[0], "dnf install -y ") || !slices.Contains(strings.Fields(got[0]), "vim-enhanced") {
		t.Errorf("calls = %q, want one dnf install with vim-enhanced and no EPEL check on Fedora", got)
	}
}

func TestEnableEPEL(t *testing.T) {
	rocky := map[string]string{"ID": "rocky", "ID_LIKE": "rhel centos fedora"}
	epelQuery := "rpm -q epel-release oracle-epel-release-el8 oracle-epel-release-el9 oracle-epel-release-el10"
	tests := []struct {
		name    string
		release map[string]string
		rpm     int  // the exit code of rpm -q
		dry     bool // a dry run
		answer  string
		dnf     int
		crb     bool
		calls   []string
		log     string
	}{
		{name: "not RHEL", release: map[string]string{"ID": "fedora", "ID_LIKE": ""}},
		{name: "on already", release: rocky, calls: []string{epelQuery}},
		{name: "RHEL has no epel-release", release: map[string]string{"ID": "rhel"}, rpm: 1, calls: []string{epelQuery}, log: "EPEL is off"},
		{name: "dry run", release: rocky, rpm: 1, dry: true, calls: []string{epelQuery}, log: "would ask to turn on EPEL"},
		{name: "no", release: rocky, rpm: 1, answer: "no", calls: []string{epelQuery}},
		{name: "yes", release: rocky, rpm: 1, answer: "yes", crb: true, calls: []string{epelQuery, "dnf install -y epel-release", "crb enable"}},
		{name: "yes, without crb", release: rocky, rpm: 1, answer: "yes", calls: []string{epelQuery, "dnf install -y epel-release"}},
		{name: "Oracle Linux", release: map[string]string{"ID": "ol", "VERSION_ID": "9.3"}, rpm: 1, answer: "yes", calls: []string{epelQuery, "dnf install -y oracle-epel-release-el9"}},
		{name: "failed install", release: rocky, rpm: 1, answer: "yes", dnf: 1, calls: []string{epelQuery, "dnf install -y epel-release"}, log: "Couldn't turn on EPEL"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			s, u, f := newTestSetup(t, "home", "full")
			fakeOSRelease(t, s, tt.release)
			asUser(t, 0)
			f.set("rpm", fakeCmd{Code: tt.rpm})
			f.set("dnf", fakeCmd{Code: tt.dnf})
			if tt.crb {
				f.set("crb", fakeCmd{})
			}
			s.DryRun = tt.dry
			if tt.answer != "" {
				u.answer(tt.answer)
			}
			if err := s.enableEPEL(); err != nil {
				t.Fatal(err)
			}
			if got := callsOf(f, "rpm", "dnf", "crb"); !slices.Equal(got, tt.calls) {
				t.Errorf("calls = %q, want %q", got, tt.calls)
			}
			if tt.log != "" && !logHas(u, tt.log) {
				t.Errorf("log = %q, want %q", u.log, tt.log)
			}
		})
	}
}

// installer writes a script that records its run in the file ran, then exits with code.
func installer(t *testing.T, dir, name string, code int) string {
	t.Helper()
	p := filepath.Join(dir, name)
	text := fmt.Sprintf("#!/usr/bin/env bash\necho %s >>%q\nexit %d\n", name, dir+"/ran", code)
	if err := os.WriteFile(p, []byte(text), 0o755); err != nil {
		t.Fatal(err)
	}
	return p
}

func TestRunInstallers(t *testing.T) {
	s, u, _ := newTestSetup(t, "home", "full")
	dir := t.TempDir()
	s.Cfg.ResolvedInstallers = []string{installer(t, dir, "bad.sh", 1), installer(t, dir, "good.sh", 0)}
	s.Cfg.InstallersErr = "envsetup: an installer folder is missing"

	// Dry run: no installer runs.
	s.DryRun = true
	if err := s.RunInstallers(); err != nil {
		t.Fatal(err)
	}
	if !logHas(u, "would run 2 installer scripts") || isFile(dir+"/ran") {
		t.Errorf("dry run: log %q, ran %v", u.log, isFile(dir+"/ran"))
	}

	// One failed installer does not stop the others.
	s.DryRun = false
	if err := s.RunInstallers(); !errors.Is(err, ErrFailed) {
		t.Errorf("RunInstallers = %v, want ErrFailed", err)
	}
	if b, _ := os.ReadFile(dir + "/ran"); string(b) != "bad.sh\ngood.sh\n" {
		t.Errorf("ran %q, want both installers", b)
	}
	if !logHas(u, "fail: Installers failed: bad.sh") {
		t.Errorf("log = %q", u.log)
	}

	s.Cfg.ResolvedInstallers = nil
	if err := s.RunInstallers(); err != nil || !logHas(u, "No installers for home.") {
		t.Errorf("no installers: %v, log %q", err, u.log)
	}
}

// TestRunInstallersPinned runs the real kubectl.sh with a fake kubectl.
func TestRunInstallersPinned(t *testing.T) {
	s, u, f := newTestSetup(t, "work", "full")
	f.set("kubectl", fakeCmd{})
	s.Cfg.ResolvedInstallers = []string{s.Root + "/installers/work/kubectl.sh"}
	pin, err := s.Pin("kubectl")
	if err != nil || pin == "" {
		t.Fatalf("Pin(kubectl) = %q, %v", pin, err)
	}
	record := s.Home + "/.local/state/envsetup/installed"
	if err := os.MkdirAll(filepath.Dir(record), 0o755); err != nil {
		t.Fatal(err)
	}
	tool := s.Home + "/.local/bin/kubectl"
	if err := os.MkdirAll(filepath.Dir(tool), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(tool, nil, 0o755); err != nil {
		t.Fatal(err)
	}

	// An installer that is up to date at its pin is skipped before it uses the network.
	if err := os.WriteFile(record, []byte("kubectl "+pin+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := s.RunInstallers(); err != nil {
		t.Fatal(err)
	}
	if logHas(u, "Updates:") {
		t.Errorf("an installer at its pin is listed as an update: %q", u.log)
	}

	// A record that differs from the pin is an update.
	if err := os.WriteFile(record, []byte("kubectl 0.0.1\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	s.DryRun = true
	if err := s.RunInstallers(); err != nil {
		t.Fatal(err)
	}
	if !logHas(u, "note:   would update kubectl 0.0.1 → "+pin) {
		t.Errorf("dry run log = %q, want the update", u.log)
	}
	s.DryRun = false
	f.set("curl", fakeCmd{Code: 22}) // the download fails
	if err := s.RunInstallers(); !errors.Is(err, ErrFailed) {
		t.Errorf("RunInstallers with a failed download = %v, want ErrFailed", err)
	}
	if !logHas(u, "note: Updates:") || !logHas(u, "kubectl 0.0.1 → "+pin) {
		t.Errorf("log = %q, want the update listed", u.log)
	}
	if !slices.ContainsFunc(f.calls(), func(c string) bool { return strings.HasPrefix(c, "curl ") }) {
		t.Errorf("calls = %q, want the download", f.calls())
	}

	// Uninstall deletes the record and keeps the tools.
	f.set("git", fakeCmd{Code: 1}) // ~/.gitconfig includes nothing
	u.answer("yes")
	if err := s.Uninstall(); err != nil {
		t.Fatal(err)
	}
	if isFile(record) {
		t.Error("Uninstall kept the record of installed tools")
	}
	if !isFile(tool) {
		t.Error("Uninstall removed the tool")
	}
}
