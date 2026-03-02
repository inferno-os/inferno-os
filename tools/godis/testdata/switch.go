package main

func classify(x int) int {
	switch x {
	case 1:
		return 10
	case 2:
		return 20
	case 3:
		return 30
	default:
		return 0
	}
}

func main() {
	println(classify(1))
	println(classify(2))
	println(classify(3))
	println(classify(99))
}
