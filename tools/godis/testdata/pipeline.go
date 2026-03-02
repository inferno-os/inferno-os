package main

func main() {
	jobs := make(chan int)
	results := make(chan int)

	// Start 3 workers as anonymous goroutines
	go func() {
		for {
			n := <-jobs
			if n == 0 {
				return
			}
			results <- n * n
		}
	}()
	go func() {
		for {
			n := <-jobs
			if n == 0 {
				return
			}
			results <- n * n
		}
	}()
	go func() {
		for {
			n := <-jobs
			if n == 0 {
				return
			}
			results <- n * n
		}
	}()

	// Send 9 jobs
	go func() {
		i := 1
		for i <= 9 {
			jobs <- i
			i = i + 1
		}
		// Send sentinel to each worker
		jobs <- 0
		jobs <- 0
		jobs <- 0
	}()

	// Collect 9 results
	sum := 0
	i := 0
	for i < 9 {
		sum = sum + <-results
		i = i + 1
	}
	println(sum)
}
