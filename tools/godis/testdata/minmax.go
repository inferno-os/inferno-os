package main

func main() {
	a := 10
	b := 3
	c := 7

	println(min(a, b))    // 3
	println(max(a, b))    // 10
	println(min(a, b, c)) // 3
	println(max(a, b, c)) // 10
	println(min(5, 5))    // 5

	// Negative numbers
	println(min(-1, 1))  // -1
	println(max(-1, 1))  // 1
}
