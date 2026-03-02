package main

func main() {
	m := make(map[string]int)
	m["a"] = 10
	m["b"] = 20

	// Multiple assignment from map without if
	v1, ok1 := m["a"]
	v2, ok2 := m["c"]
	println(v1, ok1)
	println(v2, ok2)

	// Simple map lookup (no comma-ok)
	v3 := m["b"]
	println(v3)
}
