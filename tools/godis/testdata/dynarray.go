package main

func main() {
	var arr [4]int
	arr[0] = 10
	arr[1] = 20
	arr[2] = 30
	arr[3] = 40

	// Dynamic indexing
	i := 2
	println(arr[i]) // 30

	// Sum via dynamic index loop
	sum := 0
	for j := 0; j < 4; j++ {
		sum = sum + arr[j]
	}
	println(sum) // 100
}
