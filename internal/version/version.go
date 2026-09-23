package version

import (
	"regexp"
	"strconv"

	"github.com/heliosbbs/heliosadvance/internal/fault"
)

// Version is the semantic version; the commit is stamped separately.
const Version = "0.1.0"

// Major returns the major version, Minor the minor, or InvalidClass if the
// version string does not parse as SemVer.
func Major() (int, fault.Class) {
	m, _, _, c := parse(Version)
	return m, c
}

// Minor returns the minor version, or InvalidClass if the version string does
// not parse as SemVer.
func Minor() (int, fault.Class) {
	_, m, _, c := parse(Version)
	return m, c
}

// Patch returns the patch version, or InvalidClass if the version string does
// not parse as SemVer.
func Patch() (int, fault.Class) {
	_, _, p, c := parse(Version)
	return p, c
}

func parse(v string) (major, minor, patch int, class fault.Class) {
	// Match vMAJOR.MINOR.PATCH[optional -prerelease +build].
	// SemVer 2.0.0: https://semver.org/
	re := regexp.MustCompile(`^(\d+)\.(\d+)\.(\d+)(?:-[a-zA-Z0-9.-]+)?(?:\+[a-zA-Z0-9.-]+)?$`)
	m := re.FindStringSubmatch(v)
	if m == nil {
		return 0, 0, 0, fault.InvalidClass
	}
	major, _ = strconv.Atoi(m[1])
	minor, _ = strconv.Atoi(m[2])
	patch, _ = strconv.Atoi(m[3])
	return major, minor, patch, fault.None
}
