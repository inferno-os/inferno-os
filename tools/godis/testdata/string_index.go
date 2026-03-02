package main

import "strings"

func main() {
	s := "hello world"
	// Test various string operations
	println(strings.Contains(s, "world"))
	println(strings.HasPrefix(s, "hello"))
	println(strings.Index(s, "world"))
	println(strings.ToUpper("abc"))
	upper := strings.ToUpper(s)
	println(upper)
}
