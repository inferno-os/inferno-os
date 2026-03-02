package main

import "fmt"

func main() {
	// %t: bool formatting
	println(fmt.Sprintf("%t", true))
	println(fmt.Sprintf("%t", false))

	// %q: quoted string
	println(fmt.Sprintf("%q", "hello"))

	// %b: binary
	println(fmt.Sprintf("%b", 10))

	// %o: octal
	println(fmt.Sprintf("%o", 8))

	// %05d: zero-padded width
	println(fmt.Sprintf("%05d", 42))
}
