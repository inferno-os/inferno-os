package main

func sum(nums []int) int {
	total := 0
	for i := 0; i < len(nums); i++ {
		total += nums[i]
	}
	return total
}

func main() {
	a := []int{10, 20, 30}
	println(sum(a))
	println(len(a))
}
