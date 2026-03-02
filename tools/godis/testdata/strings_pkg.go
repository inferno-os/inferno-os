package main

import "strings"

func main() {
	s := "hello world"
	if strings.Contains(s, "world") {
		println("contains")
	}
	if strings.HasPrefix(s, "hello") {
		println("prefix")
	}
	if strings.HasSuffix(s, "world") {
		println("suffix")
	}
	idx := strings.Index(s, "world")
	println(idx)
	idx2 := strings.Index(s, "xyz")
	println(idx2)
}
