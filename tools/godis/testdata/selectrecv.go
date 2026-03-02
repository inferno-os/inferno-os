package main

func sender1(ch chan int) {
	ch <- 10
}

func sender2(ch chan int) {
	ch <- 20
}

func main() {
	ch1 := make(chan int)
	ch2 := make(chan int)
	go sender1(ch1)
	go sender2(ch2)

	// Receive from whichever is ready first
	select {
	case v := <-ch1:
		println(v)
	case v := <-ch2:
		println(v)
	}
}
