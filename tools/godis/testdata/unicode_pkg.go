package main

import "unicode"

func main() {
	if unicode.IsLetter('A') {
		println("letter")
	}
	if unicode.IsDigit('5') {
		println("digit")
	}
	if unicode.IsUpper('Z') {
		println("upper")
	}
	if unicode.IsLower('a') {
		println("lower")
	}
	if unicode.IsSpace(' ') {
		println("space")
	}
	println(unicode.ToUpper('a'))
	println(unicode.ToLower('Z'))
}
