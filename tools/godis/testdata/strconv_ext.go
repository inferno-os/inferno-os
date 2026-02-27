package main

import "strconv"

func main() {
	// FormatBool
	println(strconv.FormatBool(true))
	println(strconv.FormatBool(false))
	// ParseBool
	v, _ := strconv.ParseBool("true")
	if v {
		println("parsed true")
	}
	// Quote
	println(strconv.Quote("hello"))
	// Unquote
	s, _ := strconv.Unquote("\"world\"")
	println(s)
	// ParseInt
	n, _ := strconv.ParseInt("42", 10, 64)
	println(n)
}
