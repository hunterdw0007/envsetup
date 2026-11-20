package setup

import (
	"reflect"
	"testing"
)

func TestConfigRepoURL(t *testing.T) {
	for in, want := range map[string]string{
		"":                           "",
		"me":                         "https://github.com/me/envsetup-config",
		"me/dotfiles":                "https://github.com/me/dotfiles",
		"github.com/me/dotfiles":     "https://github.com/me/dotfiles",
		"gitlab.com/me/x":            "https://gitlab.com/me/x",
		"git@github.com:me/x.git":    "git@github.com:me/x.git",
		"https://example.com/a/b":    "https://example.com/a/b",
		"/srv/git/config":            "/srv/git/config",
		"file:///srv/git/config.git": "file:///srv/git/config.git",
	} {
		if got := configRepoURL(in); got != want {
			t.Errorf("configRepoURL(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestRenameWords(t *testing.T) {
	items := []string{"ENVSETUP_OLD=ENVSETUP_NEW", "ENVSETUP_NEW=ENVSETUP_NEWER"}
	for _, tc := range []struct{ in, want string }{
		{"ENVSETUP_OLD=1\n", "ENVSETUP_NEWER=1\n"},
		{"x=$ENVSETUP_OLD # ENVSETUP_OLDER ENVSETUP_OLD_X\n", "x=$ENVSETUP_NEWER # ENVSETUP_OLDER ENVSETUP_OLD_X\n"},
		{"a\nENVSETUP_OLD+=(b)", "a\nENVSETUP_NEWER+=(b)"},
		{"\xffENVSETUP_OLD\xfe\n", "\xffENVSETUP_NEWER\xfe\n"},
	} {
		if got := renameWords(tc.in, items); got != tc.want {
			t.Errorf("renameWords(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
	if !hasWord("x ENVSETUP_OLD=1", "ENVSETUP_OLD") || hasWord("ENVSETUP_OLDER=1", "ENVSETUP_OLD") {
		t.Error("hasWord does not match whole words only")
	}
}

func TestSyntaxError(t *testing.T) {
	const f = "/tmp/x/config.sh"
	for in, want := range map[string]string{
		f + ": line 2: syntax error near unexpected token `fi'": "line 2: syntax error near unexpected token `fi'",
		f + ":2: parse error near `fi'":                         "line 2: parse error near `fi'",
	} {
		if got := syntaxError(in, f); got != want {
			t.Errorf("syntaxError(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestChanges(t *testing.T) {
	before := "Packages|git\nPackages|vim\nShell|bash\nSkip|x"
	after := "Packages|git\nPackages|neovim\nShell|zsh\nSkip|x"
	want := []string{"Packages: +neovim -vim", "Shell: +zsh -bash"}
	if got := changes(before, after); !reflect.DeepEqual(got, want) {
		t.Errorf("changes = %q, want %q", got, want)
	}
	if got := changes(before, before); got != nil {
		t.Errorf("changes of the same text = %q, want none", got)
	}
}

func TestCleanText(t *testing.T) {
	// $(<file) drops the trailing newlines before the \r removal, so "\r\n\r" keeps one newline.
	if got, want := cleanText("a=1\r\nb=2\r\n\r\n"), "a=1\nb=2\n"; got != want {
		t.Errorf("cleanText = %q, want %q", got, want)
	}
	if got := editorArgs("code --wait\nx", false); !reflect.DeepEqual(got, []string{"code", "--wait"}) {
		t.Errorf("editorArgs = %q", got)
	}
}
