package main

func main() {
	s := "hello"
	sum := 0
	for _, c := range s {
		sum = sum + int(c)
	}
	println(sum) // 104+101+108+108+111 = 532
}
