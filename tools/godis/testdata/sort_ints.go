package main

import "sort"

func main() {
	nums := []int{5, 3, 1, 4, 2}
	sort.Ints(nums)
	for _, n := range nums {
		println(n)
	}
	println(sort.IntsAreSorted(nums))
}
