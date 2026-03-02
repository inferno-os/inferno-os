package main

import "fmt"

func main() {
	name := "Alice"
	age := 30
	s := fmt.Sprintf("%s is %d years old", name, age)
	println(s)
}
