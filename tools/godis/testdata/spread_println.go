package main

func main() {
	args := []interface{}{"hello", 42}
	// This probably won't work but let's see the error
	_ = args

	// More practical: user-defined variadic with spread
	s := []string{"a", "b", "c"}
	printAll(s...)
}

func printAll(strs ...string) {
	for _, s := range strs {
		println(s)
	}
}
