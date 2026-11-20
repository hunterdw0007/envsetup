package setup

import "testing"

func TestVersionCompare(t *testing.T) {
	tests := []struct {
		a, b string
		want int // the sign only
	}{
		{"v1.0.0", "v1.0.0", 0},
		{"v1.10.0", "v1.9.0", 1},
		{"v1.2.3", "v1.2.10", -1},
		{"v2.0.0", "v10.0.0", -1},
		{"v0.15.5", "v1.0.0", -1},
		{"v01.0.0", "v1.0.0", -1}, // equal numbers, then plain string order
		{"v..", "v0.0.0", 1},      // like sort -V: a dot ranks after a digit
	}
	for _, tt := range tests {
		got := versionCompare(tt.a, tt.b)
		if sign(got) != tt.want {
			t.Errorf("versionCompare(%q, %q) = %d, want sign %d", tt.a, tt.b, got, tt.want)
		}
		if sign(versionCompare(tt.b, tt.a)) != -tt.want {
			t.Errorf("versionCompare(%q, %q) is not the reverse", tt.b, tt.a)
		}
	}
}

func sign(n int) int {
	switch {
	case n < 0:
		return -1
	case n > 0:
		return 1
	}
	return 0
}

func TestNewestTag(t *testing.T) {
	out := "abc\trefs/tags/v0.9.0\n" +
		"abc\trefs/tags/v1.10.2\n" +
		"abc\trefs/tags/v1.9.9\n" +
		"abc\trefs/tags/v2.0.0-rc1\n" +
		"abc\trefs/tags/v1.10.10\n"
	if got := newestTag(out); got != "v1.10.10" {
		t.Errorf("newestTag = %q, want v1.10.10", got)
	}
	if got := newestTag(""); got != "" {
		t.Errorf("newestTag of nothing = %q, want empty", got)
	}
}

func TestInstallerCmd(t *testing.T) {
	tests := []struct{ script, want string }{
		{"#!/usr/bin/env bash\nenvsetup::has_cmd fzf && exit 0\n", "fzf"},
		{"\tenvsetup::up_to_date kubectl kubectl && exit 0\n", "kubectl"},
		{"envsetup::has_cmd a && exit 0\nenvsetup::has_cmd b && exit 0 # last wins\n", "b"},
		{"envsetup::has_cmd fzf && exit 0", ""}, // like read, a last line without a newline does not count
		{"if envsetup::has_cmd fzf; then exit 0; fi\n", ""},
		{"echo setup step\n", ""},
	}
	for _, tt := range tests {
		if got := installerCmd(tt.script); got != tt.want {
			t.Errorf("installerCmd(%q) = %q, want %q", tt.script, got, tt.want)
		}
	}
}
