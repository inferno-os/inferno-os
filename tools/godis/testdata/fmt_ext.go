package main

import "fmt"

func main() {
	// Sprint
	s := fmt.Sprint("hello")
	println(s)
	// Print (no newline, but we add one manually)
	fmt.Print("world\n")
}
