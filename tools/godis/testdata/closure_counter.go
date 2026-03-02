package main

func makeCounter() func() int {
	n := 0
	return func() int {
		n++
		return n
	}
}

func main() {
	c := makeCounter()
	println(c())
	println(c())
	println(c())
}
