package main

import "regexp"

func main() {
	re := regexp.MustCompile("[a-z]+")
	_ = re
	matched, err := regexp.MatchString("[a-z]+", "hello")
	_ = matched
	_ = err
	println("regexp ok")
}
