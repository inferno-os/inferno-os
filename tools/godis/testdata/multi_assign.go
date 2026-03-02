package main

func main() {
	a := 1
	b := 2
	a, b = b, a
	println(a)
	println(b)
	x, y, z := 10, 20, 30
	println(x + y + z)
}
