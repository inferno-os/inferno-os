package main

import "time"

func main() {
	start := time.Now()
	time.Sleep(100 * time.Millisecond)
	elapsed := time.Since(start)

	// elapsed should be >= 100ms = 100000000ns
	if elapsed >= 50*time.Millisecond {
		println("ok")
	} else {
		println("too fast")
	}
}
