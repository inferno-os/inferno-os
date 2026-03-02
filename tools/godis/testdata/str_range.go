package main

func main() {
	s := "hello"
	count := 0
	for _, r := range s {
		if r == 'l' {
			count++
		}
	}
	println(count) // 2

	// Range with index
	s2 := "abc"
	for i, r := range s2 {
		println(i)
		_ = r
	}
}
