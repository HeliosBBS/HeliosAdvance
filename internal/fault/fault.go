package fault

import "errors"

type Class int

const (
	None Class = iota
	UnavailableClass
	ConflictClass
	RefusedClass
	InvalidClass
	DeniedClass
	NotFoundClass
	FatalClass
)

type classError struct {
	class Class
	text  string
}

func (e classError) Error() string {
	return e.text
}

var (
	Unavailable error = classError{UnavailableClass, "unavailable"}
	Conflict    error = classError{ConflictClass, "conflict"}
	Refused     error = classError{RefusedClass, "refused"}
	Invalid     error = classError{InvalidClass, "invalid"}
	Denied      error = classError{DeniedClass, "denied"}
	NotFound    error = classError{NotFoundClass, "not found"}
	Fatal       error = classError{FatalClass, "fatal"}
)

// ClassOf returns the class of an error by walking its wrap chain.
// An error carries a class only by wrapping one of the exported sentinels
// (Unavailable, Conflict, Refused, Invalid, Denied, NotFound, Fatal) with
// fmt.Errorf("%w", ...) or errors.Join(...). If multiple classes are wrapped,
// ClassOf returns the first found in depth-first order.
func ClassOf(err error) Class {
	var ce classError
	if errors.As(err, &ce) {
		return ce.class
	}
	return None
}
