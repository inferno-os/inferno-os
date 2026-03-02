package main

func main() {
	ch := make(chan int, 1)
	ch <- 42
	defer close(ch)

	v := <-ch
	println(v) // 42
}
