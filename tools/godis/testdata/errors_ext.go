package main

import "errors"

func main() {
	e1 := errors.New("oops")
	e2 := errors.New("oops")
	_ = e1
	_ = e2
	// errors.Is compares interface tags
	if errors.Is(e1, e1) {
		println("same")
	}
	// errors.Unwrap returns nil for simple errors
	e3 := errors.Unwrap(e1)
	_ = e3
	println("done")
}
