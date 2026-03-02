package main

func cleanup(m map[string]int) {
	defer delete(m, "temp")
	m["temp"] = 999
}

func main() {
	ch := make(chan int, 3)
	defer close(ch)

	ch <- 10
	ch <- 20
	ch <- 30

	println(<-ch)
	println(<-ch)
	println(<-ch)

	// Test defer delete
	m := map[string]int{"a": 1, "temp": 0}
	cleanup(m)
	// After cleanup, "temp" should be deleted
	v, ok := m["temp"]
	if ok {
		println(v)
	} else {
		println(-1)
	}
}
