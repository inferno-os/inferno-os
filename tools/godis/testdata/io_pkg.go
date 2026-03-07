package main

import "io"

func main() {
	// io.EOF is an error variable
	_ = io.EOF
	println("io ok")
}
