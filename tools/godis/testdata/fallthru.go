package main

func classify(n int) int {
	result := 0
	switch {
	case n < 0:
		result = -1
	case n == 0:
		result = 10
		fallthrough
	case n == 1:
		result += 20
	default:
		result = 99
	}
	return result
}

func main() {
	println(classify(-1)) // -1
	println(classify(0))  // 30 (10+20 via fallthrough)
	println(classify(1))  // 20
	println(classify(5))  // 99
}
