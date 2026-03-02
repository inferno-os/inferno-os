package main

func main() {
	m := make(map[string]int)
	m["a"] = 1
	m["b"] = 2
	m["c"] = 3

	// Range with value only (key unused)
	sum := 0
	for _, v := range m {
		sum = sum + v
	}
	println(sum) // 6

	// Range with int keys
	m2 := make(map[int]int)
	m2[10] = 100
	m2[20] = 200
	sum2 := 0
	for k, v := range m2 {
		sum2 = sum2 + k + v
	}
	println(sum2) // 330
}
