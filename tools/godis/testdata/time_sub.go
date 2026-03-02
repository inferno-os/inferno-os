package main

import "time"

func main() {
	start := time.Now()
	time.Sleep(50 * time.Millisecond)
	elapsed := time.Since(start)

	// Since returns Duration (nanoseconds)
	// 50ms = 50000000ns, check >= 40000000
	if elapsed >= 40*time.Millisecond {
		println("ok")
	} else {
		println("too fast")
	}
}
