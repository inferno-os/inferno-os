package main

func worker(ch chan int) {
	ch <- 42
}

func main() {
	ch := make(chan int)
	go worker(ch)
	v := <-ch
	println(v)
}
