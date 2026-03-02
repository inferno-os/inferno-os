package main

func describe(x interface{}) {
	switch v := x.(type) {
	case int:
		println("int:", v)
	case string:
		println("string:", v)
	default:
		println("unknown")
	}
}

func main() {
	describe(42)
	describe("hello")
}
