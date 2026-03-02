package main

import "errors"

func divide(a, b int) (int, error) {
	if b == 0 {
		return 0, errors.New("division by zero")
	}
	return a / b, nil
}

func main() {
	result, err := divide(10, 2)
	if err != nil {
		println(err.Error())
	} else {
		println(result)
	}

	_, err2 := divide(5, 0)
	if err2 != nil {
		println(err2.Error())
	}
}
