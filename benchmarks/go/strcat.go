package main

import "inferno/sys"

func main() {
	t1 := sys.Millisec()
	iterations := 300
	totalLen := 0
	for iter := 0; iter < iterations; iter++ {
		s := ""
		i := 0
		for i < 2000 {
			s = s + "a"
			i = i + 1
		}
		totalLen = totalLen + len(s)
	}
	t2 := sys.Millisec()
	println("BENCH strcat", t2-t1, "ms", iterations, "iters", totalLen)
}
