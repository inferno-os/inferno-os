package main

func main() {
	// Type assertion comma-ok outside if
	var x interface{} = 42
	v, ok := x.(int)
	if ok {
		println(v)
	}

	_, ok2 := x.(string)
	if ok2 {
		println("wrong")
	} else {
		println("not string")
	}

	// Map comma-ok outside if
	m := make(map[string]int)
	m["a"] = 10

	v3, ok3 := m["a"]
	if ok3 {
		println(v3)
	}

	v4, ok4 := m["z"]
	if ok4 {
		println("wrong")
	} else {
		println(v4)
	}
}
