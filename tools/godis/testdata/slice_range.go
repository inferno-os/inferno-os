package main

func main() {
	s := []int{10, 20, 30}
	sum := 0
	for i, v := range s {
		sum = sum + i + v
	}
	println(sum)
}
