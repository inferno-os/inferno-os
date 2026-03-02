package main

func main() {
	// Clear a map
	m := map[string]int{"a": 1, "b": 2, "c": 3}
	println(len(m)) // 3
	clear(m)
	println(len(m)) // 0

	// Clear a slice
	s := []int{10, 20, 30}
	clear(s)
	println(s[0]) // 0
	println(s[1]) // 0
	println(s[2]) // 0
	println(len(s)) // 3 (length unchanged)
}
