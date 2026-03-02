package main

func main() {
	ch := make(chan int, 1)
	ch <- 42

	v, ok := <-ch
	println(v)
	println(ok)

	close(ch)
	v2, ok2 := <-ch
	println(v2)
	println(ok2)
}
