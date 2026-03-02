package main

import "sync"

func main() {
	var mu sync.Mutex
	count := 0

	mu.Lock()
	count = count + 10
	mu.Unlock()

	mu.Lock()
	count = count + 20
	mu.Unlock()

	println(count) // 30
}
