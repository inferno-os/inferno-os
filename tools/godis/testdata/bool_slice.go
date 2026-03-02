package main

func main() {
	flags := make([]bool, 5)
	// All elements should be zero-initialized (false)
	count := 0
	i := 0
	for i < 5 {
		if !flags[i] {
			count = count + 1
		}
		i = i + 1
	}
	println(count)

	flags[2] = true
	if flags[2] {
		println("set")
	}
}
