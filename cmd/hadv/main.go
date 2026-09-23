// Command hadv is the Helios Advance BBS engine.
package main

import (
	"fmt"
	"os"
)

// version is stamped at build time with the exact commit, which is what the
// AGPLv3 section 13 source offer must be able to name.
var version = "dev"

func main() {
	if len(os.Args) > 1 && os.Args[1] == "version" {
		fmt.Println(version)
		return
	}
	fmt.Fprintln(os.Stderr, "hadv: nothing to run yet; see CONSTITUTION.md")
	os.Exit(2)
}
