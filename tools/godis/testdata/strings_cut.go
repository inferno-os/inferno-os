package main

import "strings"

func main() {
	before, after, found := strings.Cut("hello:world", ":")
	if found {
		println(before)
		println(after)
	}
	s, ok := strings.CutPrefix("hello world", "hello ")
	if ok {
		println(s)
	}
	s2, ok2 := strings.CutSuffix("file.txt", ".txt")
	if ok2 {
		println(s2)
	}
}
