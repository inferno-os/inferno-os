package main

func makeAdder(x int) func(int) int {
	return func(y int) int {
		return x + y
	}
}

func main() {
	add5 := makeAdder(5)
	println(add5(10))
	println(add5(20))
}
