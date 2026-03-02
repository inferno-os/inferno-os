package main

func main() {
	m := map[string]int{"a": 1, "b": 2, "c": 3}
	delete(m, "b")
	println(len(m))
}
