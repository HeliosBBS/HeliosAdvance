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
		name string
		err  error
		want Class
	}{
		{"nil", nil, None},
		{"foreign error", errors.New("x"), None},
		{"join of foreign errors", errors.Join(errors.New("a"), fmt.Errorf("b: %w", io.EOF)), None},
		{"Unavailable direct", Unavailable, Unavailable},
		{"Unavailable wrapped", fmt.Errorf("renew: %w", Unavailable), Unavailable},
		{"Conflict wrapped twice", fmt.Errorf("outer: %w", fmt.Errorf("inner: %w", Conflict)), Conflict},
		{"Refused joined", errors.Join(errors.New("context"), Refused), Refused},
		{"Invalid wrapped inside a join", errors.Join(errors.New("a"), fmt.Errorf("b: %w", Invalid)), Invalid},
		{"Denied wrapped", fmt.Errorf("gate: %w", Denied), Denied},
		{"NotFound joined", errors.Join(errors.New("x"), NotFound), NotFound},
		{"Fatal wrapped", fmt.Errorf("start: %w", Fatal), Fatal},
		{"first found wins when the later-declared class comes first", errors.Join(Fatal, Unavailable), Fatal},
		{"first found wins when the earlier-declared class comes first", errors.Join(Refused, Invalid), Refused},
		{"depth-first: a wrapped class before a bare one later in the join", errors.Join(fmt.Errorf("c: %w", Denied), Conflict), Denied},
		{"depth-first through two %w verbs", fmt.Errorf("%w %w", fmt.Errorf("x: %w", NotFound), Refused), NotFound},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			if got := ClassOf(tc.err); got != tc.want {
				t.Fatalf("ClassOf(%v) = %q, want %q", tc.err, got, tc.want)
			}
		})
	}
}

func TestErrorsIsThroughAWrap(t *testing.T) {
	t.Parallel()
	err := fmt.Errorf("renew: %w", Unavailable)
	if !errors.Is(err, Unavailable) {
		t.Fatal("errors.Is does not find the wrapped sentinel")
	}
	if errors.Is(err, Conflict) {
		t.Fatal("errors.Is matched a sentinel that is not in the chain")
	}
}
