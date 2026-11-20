package setup

import "testing"

func TestRCBlock(t *testing.T) {
	block, root := rcBlock("/d/my data", "/s/$x", "/h")
	want := RCBegin + "\n" +
		`export ENVSETUP_ROOT=/d/my\ data` + "\n" +
		`export ENVSETUP_STATE=/s/\$x ENVSETUP_STATE_HOME=/h` + "\n" +
		`[ -f "$ENVSETUP_ROOT/shell/init.sh" ] && source "$ENVSETUP_ROOT/shell/init.sh"` + "\n" +
		RCEnd + "\n"
	if block != want {
		t.Errorf("block:\n%s\nwant:\n%s", block, want)
	}
	if root != `export ENVSETUP_ROOT=/d/my\ data` {
		t.Errorf("root = %q", root)
	}
}

func TestRootLine(t *testing.T) {
	for _, tc := range []struct {
		text, want string
		ok         bool
	}{
		{"a\nexport ENVSETUP_ROOT=/x\nexport ENVSETUP_ROOT=/y\n", "export ENVSETUP_ROOT=/x", true},
		{"  export ENVSETUP_ROOT=/x\n", "", false},
		{"", "", false},
	} {
		got, ok := rootLine(tc.text)
		if got != tc.want || ok != tc.ok {
			t.Errorf("rootLine(%q) = %q, %v; want %q, %v", tc.text, got, ok, tc.want, tc.ok)
		}
	}
}

func TestHasLine(t *testing.T) {
	if !hasLine("a\nb", "b") || hasLine("ab\n", "b") || hasLine("", "") {
		t.Error("hasLine does not match whole lines")
	}
}

func TestGitKeySet(t *testing.T) {
	entries := []string{"User.Name=Me", "core.editor=vim=x", "alias.st"}
	for _, tc := range []struct {
		key  string
		want bool
	}{
		{"user.name", true},
		{"core.editor", true},
		{"alias.st", true},
		{"user.email", false},
		{"user", false},
	} {
		if got := gitKeySet(entries, tc.key); got != tc.want {
			t.Errorf("gitKeySet(%q) = %v, want %v", tc.key, got, tc.want)
		}
	}
}
