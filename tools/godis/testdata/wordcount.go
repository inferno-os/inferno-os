package main

import "strings"

func main() {
	text := "the fox and the dog and the cat"
	words := strings.Split(text, " ")

	// Count frequencies using a map
	freq := make(map[string]int)
	for i := 0; i < len(words); i++ {
		w := words[i]
		freq[w] = freq[w] + 1
	}

	// Print known words in fixed order for determinism
	known := []string{"the", "fox", "and", "dog", "cat"}
	for i := 0; i < len(known); i++ {
		w := known[i]
		c := freq[w]
		println(w, c)
	}
}
