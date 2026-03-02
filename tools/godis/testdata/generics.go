package main

// Generic Min function with type constraint
func Min[T int | float64 | string](a, b T) T {
	if a < b {
		return a
	}
	return b
}

// Generic Max
func Max[T int | float64 | string](a, b T) T {
	if a > b {
		return a
	}
	return b
}

// Generic Contains for slices
func Contains[T comparable](s []T, v T) bool {
	for _, x := range s {
		if x == v {
			return true
		}
	}
	return false
}

// Generic Map function
func Map[T any, U any](s []T, f func(T) U) []U {
	result := make([]U, len(s))
	for i, v := range s {
		result[i] = f(v)
	}
	return result
}

// Generic Pair type
type Pair[T any, U any] struct {
	First  T
	Second U
}

func NewPair[T any, U any](a T, b U) Pair[T, U] {
	return Pair[T, U]{First: a, Second: b}
}

func main() {
	// Test Min with different types
	println(Min(3, 5))
	println(Min(1.5, 2.5))
	println(Min("abc", "def"))

	// Test Max
	println(Max(3, 5))
	println(Max(1.5, 2.5))

	// Test Contains
	nums := []int{1, 2, 3, 4, 5}
	if Contains(nums, 3) {
		println("found 3")
	}
	if !Contains(nums, 9) {
		println("no 9")
	}

	// Test Map
	doubled := Map(nums, func(x int) int { return x * 2 })
	println(doubled[0])
	println(doubled[4])
}
