package main

import _ "embed"

//go:embed hello.txt
var greeting string

func main() {
	println(greeting)
}
