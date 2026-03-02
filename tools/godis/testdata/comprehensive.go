package main

func abs(x int) int {
	if x < 0 {
		return -x
	}
	return x
}

func fib(n int) int {
	a := 0
	b := 1
	i := 0
	for i < n {
		c := a + b
		a = b
		b = c
		i = i + 1
	}
	return a
}

func gcd(a, b int) int {
	for b != 0 {
		t := b
		b = a - (a/b)*b
		a = t
	}
	return a
}

func main() {
	println(abs(-42))
	println(abs(7))
	println(fib(10))
	println(gcd(48, 18))
	println("done")
}
