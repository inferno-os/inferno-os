package main

func main() {
	ch := make(chan int, 1)
	ch <- 42

	// Non-blocking recv (has item)
	select {
	case v := <-ch:
		println(v)
	default:
		println("default1")
	}

	// Non-blocking recv (empty)
	select {
	case v := <-ch:
		println(v)
	default:
		println("default2")
	}

	// Non-blocking send (buffered, has room)
	ch2 := make(chan int, 1)
	select {
	case ch2 <- 99:
		println("sent")
	default:
		println("full")
	}

	// Non-blocking send (full)
	select {
	case ch2 <- 100:
		println("sent2")
	default:
		println("full2")
	}
}
