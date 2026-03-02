package main

func main() {
	a, b := 1, 2
	a, b = b, a
	println(a)
	println(b)

	s := []int{10, 20, 30}
	s[0], s[2] = s[2], s[0]
	println(s[0])
	println(s[2])
}
