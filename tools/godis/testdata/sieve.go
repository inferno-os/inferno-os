package main

func main() {
	// Sieve of Eratosthenes up to 50
	// make([]int, 51) now zero-initializes all elements
	sieve := make([]int, 51)
	// 0 = not eliminated (prime candidate), 1 = eliminated
	i := 2
	for i <= 50 {
		if sieve[i] == 0 {
			j := i + i
			for j <= 50 {
				sieve[j] = 1
				j = j + i
			}
		}
		i = i + 1
	}
	i = 2
	for i <= 50 {
		if sieve[i] == 0 {
			println(i)
		}
		i = i + 1
	}
}
