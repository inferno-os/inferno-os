package main

import "strings"

func main() {
	// Count
	println(strings.Count("cheese", "e"))
	// EqualFold
	if strings.EqualFold("Hello", "hello") {
		println("equal")
	}
	// TrimPrefix
	println(strings.TrimPrefix("Hello World", "Hello "))
	// TrimSuffix
	println(strings.TrimSuffix("Hello World", " World"))
	// ReplaceAll
	println(strings.ReplaceAll("aabaa", "a", "x"))
	// ContainsRune
	if strings.ContainsRune("hello", 'e') {
		println("rune")
	}
	// ContainsAny
	if strings.ContainsAny("hello", "aeiou") {
		println("any")
	}
	// IndexByte
	println(strings.IndexByte("hello", 'l'))
	// LastIndex
	println(strings.LastIndex("abcabc", "bc"))
}
