package fault

import (
	"errors"
	"fmt"
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
		{"Unavailable wrapped with %w", fmt.Errorf("context: %w", Unavailable), UnavailableClass},
		{"Conflict wrapped twice with %w", fmt.Errorf("outer: %w", fmt.Errorf("inner: %w", Conflict)), ConflictClass},
		{"Unavailable wrapped once with errors.Join", errors.Join(errors.New("context"), Unavailable), UnavailableClass},
		{"Conflict wrapped twice with errors.Join", errors.Join(errors.New("a"), errors.Join(errors.New("b"), Conflict)), ConflictClass},
		{"Invalid wrapped multiple times", errors.Join(errors.New("x"), errors.Join(Refused, Invalid)), RefusedClass},
		{"Fatal wrapped with others", errors.Join(NotFound, Fatal, errors.New("info")), NotFoundClass},
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

func TestErrorsIsWithSentinels(t *testing.T) {
	t.Parallel()

	wrapped := fmt.Errorf("operation failed: %w", Unavailable)
	if !errors.Is(wrapped, Unavailable) {
		t.Errorf("errors.Is(fmt.Errorf with Unavailable, Unavailable) = false, want true")
	}
	if errors.Is(wrapped, Conflict) {
		t.Errorf("errors.Is(fmt.Errorf with Unavailable, Conflict) = true, want false")
	}
}
