package main

import "fmt"

func main() {
	// %d with int
	x := 42
	s1 := fmt.Sprintf("%d", x)
	println(s1)

	// %s with prefix
	name := "world"
	s2 := fmt.Sprintf("hello %s", name)
	println(s2)

	// No verbs
	s3 := fmt.Sprintf("no verbs here")
	println(s3)

	// %s with prefix and suffix
	s4 := fmt.Sprintf("hi %s!", name)
	println(s4)

	// %d with surrounding text
	age := 30
	s5 := fmt.Sprintf("age: %d years", age)
	println(s5)

	// Mixed %s and %d
	s6 := fmt.Sprintf("%s is %d", name, age)
	println(s6)

	// fmt.Println
	fmt.Println("from Println")
	fmt.Println("count:", x)
}
