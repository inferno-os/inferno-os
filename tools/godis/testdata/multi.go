package main

func double(x int) int {
	return x + x
}

func square(x int) int {
	return x * x
}

func main() {
	a := double(5)
	b := square(3)
	println(a + b)
}
