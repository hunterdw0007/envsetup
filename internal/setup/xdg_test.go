package setup

import (
	"os/exec"
	"strings"
	"testing"
)

func TestXDGTarget(t *testing.T) {
	t.Setenv("HOME", "/h")
	t.Setenv("XDG_CONFIG_HOME", "/h/.config")
	t.Setenv("XDG_DATA_HOME", "")
	t.Setenv("XDG_STATE_HOME", "/st")
	t.Setenv("XDG_CACHE_HOME", "")
	fence := func(lines ...string) string { return "Text:\n\n```bash\n" + strings.Join(lines, "\n") + "\n```\n" }
	tests := []struct {
		name, help, target, variable string
		ok                           bool
	}{
		{"export quoted var", fence(`export DOCKER_CONFIG="$XDG_CONFIG_HOME"/docker`), "/h/.config/docker", "DOCKER_CONFIG", true},
		{"export quoted all", fence(`export WGETRC="$XDG_CONFIG_HOME/wgetrc"`), "/h/.config/wgetrc", "WGETRC", true},
		{"export braces", fence(`export FOO=${XDG_DATA_HOME}/foo/bar.d`), "/h/.local/share/foo/bar.d", "FOO", true},
		{"export state", fence(`export LESSHISTFILE="$XDG_STATE_HOME"/less/history`), "/st/less/history", "LESSHISTFILE", true},
		{"export cache", fence(`export X_1="$XDG_CACHE_HOME"/x`), "/h/.cache/x", "X_1", true},
		{"blank lines in fence", "```\n\n  \nexport A=$XDG_CONFIG_HOME/a\n\n```", "/h/.config/a", "A", true},
		{"move only", "Supported by default.\n\nYou can move the file to _$XDG_CONFIG_HOME/htop/htoprc_.\n", "/h/.config/htop/htoprc", "", true},
		{"move directory braces", "move the directory to _${XDG_DATA_HOME}/app_", "/h/.local/share/app", "", true},
		{"move folder underscore", "move the folder to _$XDG_CONFIG_HOME/my_app_.", "/h/.config/my_app", "", true},
		{"two moves", "move the file to _$XDG_CONFIG_HOME/a_ or move the file to _$XDG_DATA_HOME/b_", "", "", false},
		{"move with code", "move the file to _$XDG_CONFIG_HOME/a_\n```\nfoo\n```", "", "", false},
		{"two code lines", fence(`export A="$XDG_CONFIG_HOME"/a`, `alias a="a -c x"`), "", "", false},
		{"no code", "Nothing here.", "", "", false},
		{"caveat version", fence(`export A="$XDG_CONFIG_HOME"/a`) + "Needs Version 2.", "", "", false},
		{"caveat since", fence(`export A="$XDG_CONFIG_HOME"/a`) + "since 1.0", "", "", false},
		{"caveat commit", fence(`export A="$XDG_CONFIG_HOME"/a`) + "see commit abc", "", "", false},
		{"caveat >=", fence(`export A="$XDG_CONFIG_HOME"/a`) + ">= 3", "", "", false},
		{"caveat <=", fence(`export A="$XDG_CONFIG_HOME"/a`) + "<= 3", "", "", false},
		{"BASH_ENV", fence(`export BASH_ENV="$XDG_CONFIG_HOME"/envrc`), "", "", false},
		{"ENV", fence(`export ENV="$XDG_CONFIG_HOME"/sh/shrc`), "", "", false},
		{"LD_PRELOAD", fence(`export LD_PRELOAD="$XDG_DATA_HOME"/lib.so`), "", "", false},
		{"DYLD", fence(`export DYLD_INSERT_LIBRARIES="$XDG_DATA_HOME"/lib.dylib`), "", "", false},
		{"COMMAND", fence(`export GIT_SSH_COMMAND="$XDG_CONFIG_HOME"/ssh`), "", "", false},
		{"ENVIRONMENT is fine", fence(`export ENVIRONMENT="$XDG_CONFIG_HOME"/e`), "/h/.config/e", "ENVIRONMENT", true},
		{"dotdot", fence(`export OUTSIDE_RC="$XDG_CONFIG_HOME"/../../outside`), "", "", false},
		{"dotdot end", fence(`export A="$XDG_CONFIG_HOME"/a/..`), "", "", false},
		{"dotdot move", "move the file to _$XDG_CONFIG_HOME/../x_", "", "", false},
		{"dots ok", fence(`export A="$XDG_CONFIG_HOME"/...x`), "/h/.config/...x", "A", true},
		{"lowercase var", fence(`export foo="$XDG_CONFIG_HOME"/a`), "", "", false},
		{"other base", fence(`export A="$XDG_RUNTIME_DIR"/a`), "", "", false},
		{"command substitution", fence(`export A="$XDG_CONFIG_HOME"/$(touch x)`), "", "", false},
		{"semicolon", fence(`export A="$XDG_CONFIG_HOME"/a; rm -rf ~`), "", "", false},
		{"space in path", fence(`export A="$XDG_CONFIG_HOME/a b"`), "", "", false},
		{"leading space", fence(` export A="$XDG_CONFIG_HOME"/a`), "", "", false},
		{"no path", fence(`export A="$XDG_CONFIG_HOME"`), "", "", false},
		{"unclosed fence", "```\nexport A=$XDG_CONFIG_HOME/a", "/h/.config/a", "A", true},
	}
	_, bashErr := exec.LookPath("bash")
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			target, variable, ok := xdgTarget(tt.help)
			if target != tt.target || variable != tt.variable || ok != tt.ok {
				t.Errorf("xdgTarget = %q, %q, %v; want %q, %q, %v", target, variable, ok, tt.target, tt.variable, tt.ok)
			}
			if bashErr != nil {
				return
			}
			// The bash version is the spec, so compare with it too.
			out, err := exec.Command("bash", "-c", `source ../../lib/xdg.sh && envsetup::xdg_target "$1"`, "bash", tt.help).Output()
			want := ""
			if ok {
				want = target + "\t" + variable + "\n"
			}
			if (err == nil) != ok || string(out) != want {
				t.Errorf("bash printed %q (err %v); Go gave %q", out, err, want)
			}
		})
	}
}

func TestUnTSV(t *testing.T) {
	if got := unTSV.Replace(`a\tb\nc\\t\\\\`); got != "a\tb\nc\\t\\\\" {
		t.Errorf("unTSV = %q", got)
	}
}

func TestSplitMove(t *testing.T) {
	old, new, v := splitMove("/h/.a\t/h/.config/a\t")
	if old != "/h/.a" || new != "/h/.config/a" || v != "" {
		t.Errorf("splitMove = %q %q %q", old, new, v)
	}
}

func TestEscapeGitRE(t *testing.T) {
	in := `/h/a.b[c]{d}(e)|f*g+h?i^j$k\l`
	want := `/h/a\.b\[c\]\{d\}\(e\)\|f\*g\+h\?i\^j\$k\\l`
	if got := escapeGitRE(in); got != want {
		t.Errorf("escapeGitRE = %q, want %q", got, want)
	}
	out, err := exec.Command("bash", "-c", `printf '%s' "$1" | sed 's/[][\.*^$+?(){}|]/\\&/g'`, "bash", in).Output()
	if err == nil && string(out) != want {
		t.Errorf("sed gave %q", out)
	}
}
