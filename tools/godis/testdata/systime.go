package main

import "inferno/sys"

func main() {
	t1 := sys.Millisec()
	sys.Sleep(100)
	t2 := sys.Millisec()
	elapsed := t2 - t1
	if elapsed >= 90 {
		println("sleep ok")
	}
}
