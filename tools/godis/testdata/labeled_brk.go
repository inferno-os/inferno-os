package main

func main() {
	sum := 0
outer:
	for i := 0; i < 10; i++ {
		for j := 0; j < 10; j++ {
			if i+j > 5 {
				break outer
			}
			sum++
		}
	}
	println(sum) // 6

	count := 0
loop:
	for i := 0; i < 5; i++ {
		for j := 0; j < 5; j++ {
			if j == 2 {
				continue loop
			}
			count++
		}
	}
	println(count) // 10
}
