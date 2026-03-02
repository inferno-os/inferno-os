package main

func main() {
	sum := 0
	for i := range 10 {
		sum += i
	}
	println(sum)

	// range over variable
	n := 5
	count := 0
	for range n {
		count++
	}
	println(count)
}
