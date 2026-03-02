package main

func main() {
	var s []int
	for i := 0; i < 5; i++ {
		s = append(s, i*10)
	}
	println(len(s))
	for i := 0; i < 5; i++ {
		println(s[i])
	}
}
