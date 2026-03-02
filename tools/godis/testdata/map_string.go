package main

func main() {
	freq := map[string]int{}
	words := []string{"hello", "world", "hello", "go", "world", "hello"}
	for i := 0; i < len(words); i++ {
		w := words[i]
		freq[w] = freq[w] + 1
	}
	println(freq["hello"])
	println(freq["world"])
	println(freq["go"])
}
