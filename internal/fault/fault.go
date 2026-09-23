// Package fault holds the error classes every contract uses.
package fault

// Class is an error class, and a sentinel is a Class: a caller wraps one with %w and
// checks it with errors.Is, and a boundary that sees a foreign error is what classifies
// it. Typed constants cannot be reassigned by another package.
type Class string

const (
	None        Class = ""
	Unavailable Class = "unavailable"
	Conflict    Class = "conflict"
	Refused     Class = "refused"
	Invalid     Class = "invalid"
	Denied      Class = "denied"
	NotFound    Class = "not found"
	Fatal       Class = "fatal"
)

func (c Class) Error() string { return string(c) }

// ClassOf is the first non-None class in a depth-first walk of the wrap chain, or None
// when the chain carries none; no class takes precedence over another. A wrapped None
// does not hide a real class found elsewhere in the chain.
func ClassOf(err error) Class {
	if c, ok := err.(Class); ok {
		return c
	}
	if joined, ok := err.(interface{ Unwrap() []error }); ok {
		for _, e := range joined.Unwrap() {
			if c := ClassOf(e); c != None {
				return c
			}
		}
		return None
	}
	if u, ok := err.(interface{ Unwrap() error }); ok {
		return ClassOf(u.Unwrap())
	}
	return None
}
