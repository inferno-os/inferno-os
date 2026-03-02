package main

func main() {
	s := make([]int, 0)
	s = append(s, 10)
	s = append(s, 20)
	s = append(s, 30)
	s = append(s, 40)

	// Sub-slice [1:3]
	t := s[1:3]
	println(len(t)) // 2
	println(t[0])   // 20
	println(t[1])   // 30

	// Sub-slice [:2]
	u := s[:2]
	println(len(u)) // 2
	println(u[0])   // 10
	println(u[1])   // 20

	// Sub-slice [2:]
	v := s[2:]
	println(len(v)) // 2
	println(v[0])   // 30
	println(v[1])   // 40
}
