package main

import "fmt"

func main() {
	println(fmt.Sprintf("%5d", 42))     // "   42"
	println(fmt.Sprintf("%05d", 42))    // "00042"
}
