package main

func asInt(x interface{}) int {
	return x.(int)
}

func tryString(x interface{}) (string, bool) {
	s, ok := x.(string)
	return s, ok
}

func main() {
	println(asInt(42))

	s, ok := tryString("hello")
	if ok {
		println(s)
	}
}
