package main

func main() {
	m := map[string]int{"x": 10, "y": 20}

	v1, ok1 := m["x"]
	println(v1)  // 10
	println(ok1) // true → 1

	v2, ok2 := m["z"]
	println(v2)  // 0
	println(ok2) // false → 0
}
