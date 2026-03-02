package main

func main() {
	m := make(map[string]int)
	m["hello"] = 10
	m["world"] = 20
	v1 := m["hello"]
	v2 := m["world"]
	println(v1, v2)
	m["hello"] = 30
	v3 := m["hello"]
	println(v3)
	v4, ok := m["missing"]
	println(v4, ok)
	delete(m, "hello")
	v5 := m["hello"]
	println(v5)
}
