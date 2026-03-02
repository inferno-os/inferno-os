package main

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}

func main() {
	println(max(10, 20))
}
