package main

func classify(s string) int {
	if s == "hello" {
		return 1
	}
	if s == "world" {
		return 2
	}
	return 0
}

func longer(a, b string) string {
	if len(a) > len(b) {
		return a
	}
	return b
}

func main() {
	println(classify("hello"))
	println(classify("world"))
	println(classify("other"))
	println(longer("hi", "hello"))
}
