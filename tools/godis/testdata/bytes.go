package main

func main() {
	buf := []byte{72, 101, 108, 108, 111} // "Hello"
	sum := 0
	for i := 0; i < len(buf); i++ {
		sum = sum + int(buf[i])
	}
	println(sum) // 72+101+108+108+111 = 500
	println(len(buf))
}
