// Command hadv is the Helios Advance BBS engine.
package main

import (
	"fmt"
	"os"
	"runtime/debug"
)

// version is the release tag, stamped by the release build; otherwise the
// exact commit Go recorded, which is what the AGPLv3 section 13 source offer
// must be able to name.
var version = ""

func buildVersion() string {
	if version != "" {
		return version
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
		fmt.Println(buildVersion())
		return
	}
	fmt.Fprintln(os.Stderr, "hadv: nothing to run yet; see CONSTITUTION.md")
	os.Exit(2)
}
