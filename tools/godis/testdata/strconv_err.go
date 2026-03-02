package main

import "strconv"

func main() {
	n, err := strconv.Atoi("123")
	if err != nil {
		println("error!")
	} else {
		println(n)
		println("no error")
	}

	_, err2 := strconv.Atoi("abc")
	if err2 != nil {
		println("error!")
	} else {
		println("no error 2")
	}
}
