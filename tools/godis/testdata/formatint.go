package main

import "strconv"

func main() {
	println(strconv.FormatInt(255, 16))
	println(strconv.FormatInt(10, 2))
	println(strconv.FormatInt(8, 8))
	println(strconv.FormatInt(0, 16))
}
