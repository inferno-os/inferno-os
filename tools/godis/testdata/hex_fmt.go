package main

import "fmt"

func main() {
	s1 := fmt.Sprintf("%x", 255)
	println(s1)
	s2 := fmt.Sprintf("%x", 0)
	println(s2)
	s3 := fmt.Sprintf("%x", 16)
	println(s3)
	s4 := fmt.Sprintf("val: %x", 171)
	println(s4)
}
