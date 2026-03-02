package main

func loop(n int) int {
	sum := 0
	i := 0
	for i < n {
		sum = sum + i
		i = i + 1
	}
	return sum
}

func main() {
	println(loop(5))
	println(loop(10))
}
