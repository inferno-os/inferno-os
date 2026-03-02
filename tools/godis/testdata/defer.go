package main

func greet(s string) {
	println(s)
}

func main() {
	defer greet("third")
	defer greet("second")
	defer greet("first")
	println("hello")
}
