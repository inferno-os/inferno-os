package main

func main() {
	i := 0
loop:
	if i >= 5 {
		goto done
	}
	i++
	goto loop
done:
	println(i)
}
