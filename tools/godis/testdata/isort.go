package main

func insertionSort(a []int) {
	for i := 1; i < len(a); i++ {
		key := a[i]
		j := i - 1
		for j >= 0 && a[j] > key {
			a[j+1] = a[j]
			j = j - 1
		}
		a[j+1] = key
	}
}

func main() {
	a := []int{5, 3, 8, 1, 9, 2, 7, 4, 6}
	insertionSort(a)
	for i := 0; i < len(a); i++ {
		println(a[i])
	}
}
