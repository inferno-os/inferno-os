package main

func main() {
	s := "hello world"

	// String indexing
	println(s[0])  // 104 (h)
	println(s[4])  // 111 (o)
	println(s[6])  // 119 (w)

	// String slicing
	t := s[0:5]
	println(t) // hello

	u := s[6:]
	println(u) // world

	v := s[:5]
	println(v) // hello
}
