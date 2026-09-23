package version

import (
	"testing"

	"github.com/heliosbbs/heliosadvance/internal/fault"
)

func TestMajorMinorIgnoresPreReleaseAndBuild(t *testing.T) {
	t.Parallel()

	// Parse once to verify the constant format.
	majorN, _ := Major()
	minorN, _ := Minor()
	patchN, _ := Patch()
	if majorN != 0 || minorN != 1 || patchN != 0 {
		t.Fatalf("Version constant is %d.%d.%d, want 0.1.0", majorN, minorN, patchN)
	}

	tests := []struct {
		input     string
		major     int
		minor     int
		patch     int
		wantErr   bool
		wantClass fault.Class
	}{
		{"0.1.0", 0, 1, 0, false, fault.None},
		{"0.1.0-dev", 0, 1, 0, false, fault.None},
		{"0.1.0+abc", 0, 1, 0, false, fault.None},
		{"0.1.0-dev+abc", 0, 1, 0, false, fault.None},
		{"1.2.3", 1, 2, 3, false, fault.None},
		{"1.2.3-alpha.1", 1, 2, 3, false, fault.None},
		{"2.0.0-rc.1+build.123", 2, 0, 0, false, fault.None},
		{"not.semver", 0, 0, 0, true, fault.InvalidClass},
		{"1.2", 0, 0, 0, true, fault.InvalidClass},
		{"v1.2.3", 0, 0, 0, true, fault.InvalidClass},
		{"1.2.3.4", 0, 0, 0, true, fault.InvalidClass},
	}

	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			maj, minc, pat, c := parse(tt.input)
			if c != tt.wantClass {
				t.Errorf("parse(%q) class = %v, want %v", tt.input, c, tt.wantClass)
			}
			if !tt.wantErr {
				if maj != tt.major {
					t.Errorf("parse(%q) major = %d, want %d", tt.input, maj, tt.major)
				}
				if minc != tt.minor {
					t.Errorf("parse(%q) minor = %d, want %d", tt.input, minc, tt.minor)
				}
				if pat != tt.patch {
					t.Errorf("parse(%q) patch = %d, want %d", tt.input, pat, tt.patch)
				}
			}
		})
	}
}
