package main

func sum(nums ...int) int {
	total := 0
	for _, n := range nums {
		total += n
	}
	return total
}

func main() {
	// Direct variadic call - probably works
	println(sum(1, 2, 3))

	// Slice spread - the thing we're testing
	s := []int{10, 20, 30}
	println(sum(s...))
}
