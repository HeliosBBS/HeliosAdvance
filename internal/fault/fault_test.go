package fault

import (
	"errors"
	"fmt"
	"io"
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
		{"Invalid wrapped with %w", fmt.Errorf("context: %w", Invalid), InvalidClass},
		{"Denied wrapped with %w", fmt.Errorf("context: %w", Denied), DeniedClass},
		{"Fatal wrapped with %w", fmt.Errorf("context: %w", Fatal), FatalClass},
		{"Conflict wrapped twice with %w", fmt.Errorf("outer: %w", fmt.Errorf("inner: %w", Conflict)), ConflictClass},
		{"Unavailable wrapped once with errors.Join", errors.Join(errors.New("context"), Unavailable), UnavailableClass},
		{"Invalid wrapped with errors.Join", errors.Join(Invalid), InvalidClass},
		{"Denied wrapped with errors.Join", errors.Join(errors.New("x"), Denied), DeniedClass},
		{"Fatal wrapped with errors.Join", errors.Join(errors.New("x"), errors.New("y"), Fatal), FatalClass},
		{"Conflict wrapped twice with errors.Join", errors.Join(errors.New("a"), errors.Join(errors.New("b"), Conflict)), ConflictClass},
		{"first class found wins: Refused before Invalid", errors.Join(errors.New("x"), errors.Join(Refused, Invalid)), RefusedClass},
		{"first class found wins: NotFound before Fatal", errors.Join(NotFound, Fatal, errors.New("info")), NotFoundClass},
		{"breadth-first: Refused found before Invalid in Join", errors.Join(fmt.Errorf("c: %w", Refused), Invalid), RefusedClass},
		{"all foreign errors", errors.Join(errors.New("a"), fmt.Errorf("b: %w", io.EOF)), None},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
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
