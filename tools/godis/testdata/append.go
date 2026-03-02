package main

func main() {
	s := make([]int, 0)
	s = append(s, 10)
	s = append(s, 20)
	s = append(s, 30)
	println(len(s))
	println(s[0])
	println(s[1])
	println(s[2])
}
