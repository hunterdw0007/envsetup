// Command envsetup sets up this machine's shell, git, packages and tools.
// install.sh downloads it, and setup.sh runs it from a clone.
package main

import (
	"os"

	"github.com/hunterdw0007/envsetup/internal/setup"
)

// version is set at build time with -ldflags "-X main.version=...".
var version string

func main() {
	os.Exit(setup.Main(os.Args[1:], version))
}
