package main

func pinger(ch chan string) {
	ch <- "ping"
}

func main() {
	ch := make(chan string)
	go pinger(ch)
	msg := <-ch
	println(msg)
}
