package main

func reverse(s []int) []int {
	n := len(s)
	r := make([]int, n)
	for i := 0; i < n; i++ {
		r[n-1-i] = s[i]
	}
	return r
}

func main() {
	nums := []int{1, 2, 3, 4, 5}
	rev := reverse(nums)
	for i := 0; i < len(rev); i++ {
		println(rev[i])
	}
}
