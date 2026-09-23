// SPDX-FileCopyrightText: 2026 Pascal Fairchild
// SPDX-License-Identifier: AGPL-3.0-only

// Package fault holds the error classes every contract uses.
package fault

// Class is an error class, and a sentinel is a Class: a caller wraps one with %w and
// checks it with errors.Is, and a boundary that sees a foreign error is what classifies
// it. ClassOf recognises only the seven declared classes below; a zero Class or any
// other conversion in a wrap chain is not one of them.
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
// an error whose Is or As method claims a sentinel is not classified, so a boundary
// that wants a class wraps one.
func ClassOf(err error) (Class, bool) {
	// errors.As would stop at the first Class of any value, so an undeclared one would
	// hide a declared class after it; this walks the chain in errors.As's order instead.
	if c, ok := err.(Class); ok {
		switch c {
		case Unavailable, Conflict, Refused, Invalid, Denied, NotFound, Fatal:
			return c, true
		}
	}
	switch e := err.(type) {
	case interface{ Unwrap() error }:
		return ClassOf(e.Unwrap())
	case interface{ Unwrap() []error }:
		for _, inner := range e.Unwrap() {
			if c, ok := ClassOf(inner); ok {
				return c, true
			}
		}
	}
	return "", false
}
