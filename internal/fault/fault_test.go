package fault

import (
	"errors"
	"fmt"
	"io"
	"testing"
)

// claimsDenied says it is Denied to errors.Is without carrying a Class.
type claimsDenied struct{}

func (claimsDenied) Error() string   { return "claims denied" }
func (claimsDenied) Is(t error) bool { return t == Denied }

func TestClassOf(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name string
		err  error
		want Class
		ok   bool
	}{
		{"nil", nil, "", false},
		{"foreign error", errors.New("x"), "", false},
		{"join of foreign errors", errors.Join(errors.New("a"), fmt.Errorf("b: %w", io.EOF)), "", false},
		{"an Is method claiming a sentinel carries no class", fmt.Errorf("w: %w", claimsDenied{}), "", false},
		{"Unavailable direct", Unavailable, Unavailable, true},
		{"Unavailable wrapped", fmt.Errorf("renew: %w", Unavailable), Unavailable, true},
		{"Conflict wrapped twice", fmt.Errorf("outer: %w", fmt.Errorf("inner: %w", Conflict)), Conflict, true},
		{"Refused joined", errors.Join(errors.New("context"), Refused), Refused, true},
		{"Invalid wrapped inside a join", errors.Join(errors.New("a"), fmt.Errorf("b: %w", Invalid)), Invalid, true},
		{"Denied wrapped", fmt.Errorf("gate: %w", Denied), Denied, true},
		{"NotFound joined", errors.Join(errors.New("x"), NotFound), NotFound, true},
		{"Fatal wrapped", fmt.Errorf("start: %w", Fatal), Fatal, true},
		{"first found wins when the later-declared class comes first", errors.Join(Fatal, Unavailable), Fatal, true},
		{"first found wins when the earlier-declared class comes first", errors.Join(Refused, Invalid), Refused, true},
		{"depth-first: a wrapped class before a bare one later in the join", errors.Join(fmt.Errorf("c: %w", Denied), Conflict), Denied, true},
		{"depth-first through two %w verbs", fmt.Errorf("%w %w", fmt.Errorf("x: %w", NotFound), Refused), NotFound, true},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			got, ok := ClassOf(tc.err)
			if got != tc.want || ok != tc.ok {
				t.Fatalf("ClassOf(%v) = %q, %v; want %q, %v", tc.err, got, ok, tc.want, tc.ok)
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
