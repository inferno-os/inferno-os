package main

import "os"

func main() {
	// os.ReadFile returns ([]byte, error)
	data, err := os.ReadFile("/dev/null")
	_ = data
	_ = err
	// os.WriteFile returns error
	err2 := os.WriteFile("/tmp/test", nil, 0644)
	_ = err2
	println("os ok")
}
