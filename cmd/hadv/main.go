// Command hadv is the Helios Advance BBS engine.
package main

import (
	"fmt"
	"os"
	"runtime/debug"

	"github.com/heliosbbs/heliosadvance/internal/version"
)

// releaseTag is the release tag, stamped by the release build; otherwise the
// exact commit Go recorded, which is what the AGPLv3 section 13 source offer
// must be able to name.
var releaseTag = ""

func buildVersion() string {
	if releaseTag != "" {
		return releaseTag
	}
	info, ok := debug.ReadBuildInfo()
	if !ok {
		return "unknown"
	}
	rev, modified := "unknown", ""
	for _, s := range info.Settings {
		switch s.Key {
		case "vcs.revision":
			rev = s.Value
		case "vcs.modified":
			if s.Value == "true" {
				modified = "-dirty"
			}
		}
	}
	return rev + modified
}

func main() {
	if len(os.Args) > 1 && os.Args[1] == "version" {
		fmt.Printf("%s (%s)\n", version.Version, buildVersion())
		return
	}
	fmt.Fprintln(os.Stderr, "hadv: nothing to run yet; see CONSTITUTION.md")
	os.Exit(2)
}
