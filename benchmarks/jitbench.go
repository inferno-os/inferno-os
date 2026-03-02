// jitbench.go - Go equivalent of Limbo jitbench.b
//
// Same 6 benchmarks with identical parameters for cross-language comparison.
// Uses int64 to match Limbo's 64-bit int.
//
// Run:
//   go run jitbench.go
//
// Or build and run:
//   go build -o jitbench_go jitbench.go && ./jitbench_go

package main

import (
	"fmt"
	"time"
)

const (
	ITERATIONS = 10000000
	SMALL_ITER = 1000000
)

func millisec() int64 {
	return time.Now().UnixMilli()
}

func warmup() {
	sum := int64(0)
	for i := int64(0); i < 10000; i++ {
		sum += i
	}
}

func benchArithmetic() int64 {
	a := int64(1)
	b := int64(2)
	c := int64(3)

	for i := int64(0); i < ITERATIONS; i++ {
		a = a + b
		b = b * 3
		c = c - a
		a = a ^ b
		b = b & 0xFFFF
		c = c | 0x1
		a = a << 1
		b = b >> 1
		c = c + (a % 17)
	}
	return a + b + c
}

func benchArray() int64 {
	arr := make([]int64, 1000)

	for i := 0; i < 1000; i++ {
		arr[i] = int64(i)
	}

	sum := int64(0)
	for j := int64(0); j < SMALL_ITER; j++ {
		for i := 0; i < 1000; i++ {
			sum += arr[i]
		}
	}
	return sum
}

func helperAdd(a, b int64) int64 {
	return a + b
}

func benchCalls() int64 {
	sum := int64(0)
	for i := int64(0); i < SMALL_ITER; i++ {
		sum += helperAdd(i, i+1)
	}
	return sum
}

func fib(n int64) int64 {
	if n <= 1 {
		return n
	}
	return fib(n-1) + fib(n-2)
}

func benchFib() int64 {
	sum := int64(0)
	for i := 0; i < 100; i++ {
		sum += fib(25)
	}
	return sum
}

func benchSieve() int64 {
	const SIZE = 100000
	sieve := make([]int64, SIZE)
	count := int64(0)

	for iter := 0; iter < 10; iter++ {
		for i := 0; i < SIZE; i++ {
			sieve[i] = 1
		}

		sieve[0] = 0
		sieve[1] = 0

		for i := 2; int64(i)*int64(i) < SIZE; i++ {
			if sieve[i] != 0 {
				for j := i * i; j < SIZE; j += i {
					sieve[j] = 0
				}
			}
		}

		count = 0
		for i := 0; i < SIZE; i++ {
			if sieve[i] != 0 {
				count++
			}
		}
	}
	return count
}

func benchNested() int64 {
	sum := int64(0)
	for i := int64(0); i < 500; i++ {
		for j := int64(0); j < 500; j++ {
			for k := int64(0); k < 200; k++ {
				sum += i + j + k
			}
		}
	}
	return sum
}

func main() {
	fmt.Println("=== JIT Benchmark Suite (Go) ===")
	fmt.Printf("Iterations: %d (arithmetic), %d (other)\n\n", ITERATIONS, SMALL_ITER)

	warmup()

	t0 := millisec()

	fmt.Println("1. Integer Arithmetic")
	t1 := millisec()
	result := benchArithmetic()
	t2 := millisec()
	fmt.Printf("   Result: %d, Time: %d ms\n\n", result, t2-t1)

	fmt.Println("2. Loop with Array Access")
	t1 = millisec()
	result = benchArray()
	t2 = millisec()
	fmt.Printf("   Result: %d, Time: %d ms\n\n", result, t2-t1)

	fmt.Println("3. Function Calls")
	t1 = millisec()
	result = benchCalls()
	t2 = millisec()
	fmt.Printf("   Result: %d, Time: %d ms\n\n", result, t2-t1)

	fmt.Println("4. Fibonacci (recursive)")
	t1 = millisec()
	result = benchFib()
	t2 = millisec()
	fmt.Printf("   Result: %d, Time: %d ms\n\n", result, t2-t1)

	fmt.Println("5. Sieve of Eratosthenes")
	t1 = millisec()
	result = benchSieve()
	t2 = millisec()
	fmt.Printf("   Result: %d primes, Time: %d ms\n\n", result, t2-t1)

	fmt.Println("6. Nested Loops")
	t1 = millisec()
	result = benchNested()
	t2 = millisec()
	fmt.Printf("   Result: %d, Time: %d ms\n\n", result, t2-t1)

	tend := millisec()
	fmt.Printf("=== Total Time: %d ms ===\n", tend-t0)
}
