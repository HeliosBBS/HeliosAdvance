package fault

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
}

func (e classError) Error() string {
	switch e.class {
	case UnavailableClass:
		return "unavailable"
	case ConflictClass:
		return "conflict"
	case RefusedClass:
		return "refused"
	case InvalidClass:
		return "invalid"
	case DeniedClass:
		return "denied"
	case NotFoundClass:
		return "not found"
	case FatalClass:
		return "fatal"
	default:
		return "unknown"
	}
}

var (
	Unavailable error = classError{UnavailableClass}
	Conflict    error = classError{ConflictClass}
	Refused     error = classError{RefusedClass}
	Invalid     error = classError{InvalidClass}
	Denied      error = classError{DeniedClass}
	NotFound    error = classError{NotFoundClass}
	Fatal       error = classError{FatalClass}
)

func ClassOf(err error) Class {
	if err == nil {
		return None
	}
	return classOfMax(err)
}

func classOfMax(err error) Class {
	// Check the error directly
	if ce, ok := err.(classError); ok {
		return ce.class
	}

	// Unwrap and check each wrapped error, return the maximum class found
	maxClass := None
	if uw, ok := err.(interface{ Unwrap() []error }); ok {
		for _, e := range uw.Unwrap() {
			class := classOfMax(e)
			if class > maxClass {
				maxClass = class
			}
		}
	}

	return maxClass
}
