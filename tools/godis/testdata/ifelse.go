package main

func classify(x int) int {
	var result int
	if x > 0 {
		result = 1
	} else {
		result = -1
	}
	return result
}

func main() {
	println(classify(42))
	println(classify(-5))
	println(classify(0))
}
