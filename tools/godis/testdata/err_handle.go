package main

import (
	"errors"
	"strconv"
)

func divide(a, b int) (int, error) {
	if b == 0 {
		return 0, errors.New("division by zero")
	}
	return a / b, nil
}

func main() {
	r1, err := divide(10, 2)
	if err != nil {
		println(err.Error())
	} else {
		println(r1)
	}

	_, err2 := divide(10, 0)
	if err2 != nil {
		println(err2.Error())
	}

	n, err3 := strconv.Atoi("123")
	if err3 != nil {
		println("parse error")
	} else {
		println(n)
	}
}
