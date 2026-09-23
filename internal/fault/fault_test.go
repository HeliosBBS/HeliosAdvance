package fault

import (
	"errors"
	"testing"
)

func TestClassOf(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name  string
		err   error
		class Class
	}{
		{"nil", nil, None},
		{"unwrapped stdlib error", errors.New("something"), None},
		{"Unavailable direct", Unavailable, UnavailableClass},
		{"Conflict direct", Conflict, ConflictClass},
		{"Refused direct", Refused, RefusedClass},
		{"Invalid direct", Invalid, InvalidClass},
		{"Denied direct", Denied, DeniedClass},
		{"NotFound direct", NotFound, NotFoundClass},
		{"Fatal direct", Fatal, FatalClass},
		{"Unavailable wrapped once", errors.Join(errors.New("context"), Unavailable), UnavailableClass},
		{"Conflict wrapped twice", errors.Join(errors.New("a"), errors.Join(errors.New("b"), Conflict)), ConflictClass},
		{"Invalid wrapped multiple times", errors.Join(errors.New("x"), errors.Join(Refused, Invalid)), InvalidClass},
		{"Fatal wrapped with others", errors.Join(NotFound, Fatal, errors.New("info")), FatalClass},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := ClassOf(tt.err)
			if got != tt.class {
				t.Errorf("ClassOf(%v) = %v, want %v", tt.err, got, tt.class)
			}
		})
	}
}
