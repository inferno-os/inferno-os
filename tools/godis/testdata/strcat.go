package main

func greet(first, last string) string {
	return first + " " + last
}

func main() {
	msg := greet("hello", "world")
	println(msg)
}
