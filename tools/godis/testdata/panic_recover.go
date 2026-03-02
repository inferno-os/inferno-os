package main

func safeDivide(a, b int) int {
	defer func() {
		if r := recover(); r != nil {
			println("recovered")
		}
	}()
	return a / b
}

func main() {
	println(safeDivide(10, 2)) // 5
	println(safeDivide(10, 0)) // recovered, then 0
}
