package main

import (
	"fmt"
	"time"
)

type Shape interface {
	Area() int
}

type Rect struct {
	W, H int
}

func (r Rect) Area() int {
	return r.W * r.H
}

type Circle struct {
	R int
}

func (c Circle) Area() int {
	return c.R * c.R * 3
}

func sumAreas(shapes []Shape) int {
	total := 0
	for i := 0; i < len(shapes); i++ {
		total += shapes[i].Area()
	}
	return total
}

func main() {
	t1 := time.Now()
	iterations := 1000
	total := 0
	for iter := 0; iter < iterations; iter++ {
		shapes := make([]Shape, 2000)
		for i := 0; i < 2000; i++ {
			if i%2 == 0 {
				shapes[i] = Rect{W: i, H: i + 1}
			} else {
				shapes[i] = Circle{R: i}
			}
		}
		total += sumAreas(shapes)
	}
	elapsed := time.Since(t1).Milliseconds()
	fmt.Printf("BENCH interface %d ms %d iters %d\n", elapsed, iterations, total)
}
