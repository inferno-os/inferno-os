package main

type MyInt = int

func add(a, b MyInt) MyInt {
	return a + b
}

func main() {
	var x MyInt = 10
	var y MyInt = 20
	println(add(x, y))
}
