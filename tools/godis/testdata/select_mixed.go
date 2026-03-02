package main

func main() {
	ch1 := make(chan int, 1)
	ch2 := make(chan int) // unbuffered

	ch1 <- 10

	// ch1 recv is ready (has data), ch2 send blocks (no receiver)
	select {
	case v := <-ch1:
		println(v)
	case ch2 <- 20:
		println(20)
	}

	// Now test send case firing: ch1 empty, ch2 buffered with room
	ch3 := make(chan int, 1)

	select {
	case v := <-ch1: // empty, won't fire
		_ = v
		println(-1)
	case ch3 <- 30: // buffered with room, will fire
		println(30)
	}
}
