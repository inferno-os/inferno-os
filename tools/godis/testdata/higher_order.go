package main

func double(x int) int { return x * 2 }
func triple(x int) int { return x * 3 }

func applyTwice(f func(int) int, x int) int {
	return f(f(x))
}

func main() {
	println(applyTwice(double, 3))
	println(applyTwice(triple, 2))
}
