package main

func main() {
	s := "Hello"
	runes := []rune(s)
	println(len(runes))
	s2 := string(runes)
	println(s2)
}
