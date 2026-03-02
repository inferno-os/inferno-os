package main

func main() {
	nums := []int{10, 20, 30}
	sum := 0
	for _, v := range nums {
		sum = sum + v
	}
	println(sum)
}
