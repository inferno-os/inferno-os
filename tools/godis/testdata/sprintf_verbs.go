package main

import "fmt"

func main() {
	s := fmt.Sprintf("char: %c", 65)
	println(s)

	s2 := fmt.Sprintf("hex: %x", 255)
	println(s2)

	s3 := fmt.Sprintf("%c%c%c", 72, 105, 33)
	println(s3)
}
