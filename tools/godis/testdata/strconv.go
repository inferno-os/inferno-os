package main

import "strconv"

func main() {
	s := strconv.Itoa(42)
	println(s) // "42"

	n, _ := strconv.Atoi("123")
	println(n) // 123

	// Convert rune to string (character)
	c := string(rune(65))
	println(c) // "A"
}
