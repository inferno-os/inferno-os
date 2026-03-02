package main

func main() {
	ch := make(chan int, 5)
	println(cap(ch))
	ch2 := make(chan int)
	println(cap(ch2))
}
