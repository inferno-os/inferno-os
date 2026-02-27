package main

import "runtime"

func main() {
	n := runtime.NumCPU()
	println(n)
	m := runtime.GOMAXPROCS(1)
	println(m)
	runtime.Gosched()
	println("runtime ok")
}
