package main

func send(ch chan<- int, v int) {
	ch <- v
}

func recv(ch <-chan int) int {
	return <-ch
}

func main() {
	ch := make(chan int, 1)
	send(ch, 42)
	println(recv(ch))
}
