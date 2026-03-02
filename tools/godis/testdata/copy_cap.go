package main

func main() {
	s := make([]int, 0)
	s = append(s, 1)
	s = append(s, 2)
	s = append(s, 3)
	println(cap(s)) // 3

	// Copy into larger dst
	dst := make([]int, 5)
	n := copy(dst, s)
	println(n)      // 3
	println(dst[0]) // 1
	println(dst[1]) // 2
	println(dst[2]) // 3

	// Copy into smaller dst
	small := make([]int, 2)
	n2 := copy(small, s)
	println(n2)       // 2
	println(small[0]) // 1
	println(small[1]) // 2
}
