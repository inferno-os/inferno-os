package main

import "inferno/sys"

func worker(ch chan int, done chan int) {
	// This will block in RECV until close() sends the sentinel
	v := <-ch
	done <- v
}

func main() {
	ch := make(chan int)
	done := make(chan int, 1)

	go worker(ch, done)

	// Give the goroutine time to block on RECV
	sys.Sleep(100)

	// Close the channel — this should unblock the worker via sentinel
	close(ch)

	// Wait for the worker to finish (receives 0 sentinel)
	result := <-done
	println(result)
}
