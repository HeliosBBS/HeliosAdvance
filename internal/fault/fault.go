// Package fault holds the error classes every contract uses.
package fault

import "errors"

// Class is an error class, and a sentinel is a Class: a caller wraps one with %w and
// checks it with errors.Is, and a boundary that sees a foreign error is what classifies
// it. Typed constants cannot be reassigned by another package, and there is no value
// meaning "no class", so no chain can carry one.
type Class string

const (
	Unavailable Class = "unavailable"
	Conflict    Class = "conflict"
	Refused     Class = "refused"
	Invalid     Class = "invalid"
	Denied      Class = "denied"
	NotFound    Class = "not found"
	Fatal       Class = "fatal"
)

func (c Class) Error() string { return string(c) }

// ClassOf is the first class in a depth-first walk of the wrap chain and whether one
// was found; no class takes precedence over another. Only a Class in the chain counts:
// an error whose Is method claims a sentinel is not classified, so a boundary that
// wants a class wraps one.
func ClassOf(err error) (Class, bool) {
	var c Class
	ok := errors.As(err, &c)
	return c, ok
}
