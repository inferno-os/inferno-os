package main

func main() {
	result := ""
	for i := 0; i < 5; i++ {
		result += "ab"
	}
	println(len(result))
	println(result)
}
