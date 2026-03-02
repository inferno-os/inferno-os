package main

func partition(a []int, lo, hi int) int {
	pivot := a[hi]
	i := lo
	j := lo
	for j < hi {
		if a[j] < pivot {
			tmp := a[i]
			a[i] = a[j]
			a[j] = tmp
			i = i + 1
		}
		j = j + 1
	}
	tmp := a[i]
	a[i] = a[hi]
	a[hi] = tmp
	return i
}

func quicksort(a []int, lo, hi int) {
	if lo < hi {
		p := partition(a, lo, hi)
		quicksort(a, lo, p-1)
		quicksort(a, p+1, hi)
	}
}

func main() {
	a := []int{5, 3, 8, 1, 9, 2, 7, 4, 6}
	quicksort(a, 0, len(a)-1)
	for i := 0; i < len(a); i++ {
		println(a[i])
	}
}
