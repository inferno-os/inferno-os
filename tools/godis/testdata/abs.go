package main

func abs(x int) int {
	if x < 0 {
		return -x
	}
	return x
}

func main() {
	println(abs(-7))
	println(abs(3))
}
