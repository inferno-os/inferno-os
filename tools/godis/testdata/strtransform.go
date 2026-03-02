package main

import "strings"

func main() {
	// TrimSpace
	println(strings.TrimSpace("  hello  "))

	// ToUpper / ToLower
	println(strings.ToUpper("hello"))
	println(strings.ToLower("WORLD"))

	// Repeat
	println(strings.Repeat("ab", 3))

	// Replace
	println(strings.Replace("aabaa", "a", "x", -1))

	// Split + Join
	parts := strings.Split("one-two-three", "-")
	println(strings.Join(parts, ", "))
}
